#!/usr/bin/env python3
"""Token-protected Coze bridge backed only by the Python LangGraph runtime."""

from __future__ import annotations

import hmac
import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Tuple

from langgraph_runtime import AdapterError, ProductCrewLangGraphRuntime, RuntimeBlocked


class BridgeApplication:
    def __init__(self, workspace: str | Path, skill_root: str | Path, token: str, delegate_secret: str, rag_provider: Any = None):
        if not token:
            raise ValueError("PCO_RUNTIME_TOKEN is required")
        if not delegate_secret:
            raise ValueError("PCO_LANGGRAPH_DELEGATE_SECRET is required for real delegate callbacks")
        self.token = token
        self.runtime = ProductCrewLangGraphRuntime(workspace, skill_root, delegate_secret=delegate_secret, rag_provider=rag_provider)

    def close(self) -> None:
        self.runtime.close()

    def authorize(self, authorization: str) -> bool:
        expected = f"Bearer {self.token}"
        return hmac.compare_digest(authorization or "", expected)

    def handle(self, method: str, path: str, payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        if method == "GET" and path == "/health":
            return HTTPStatus.OK, {"status": "ok", "runtime": "python_langgraph"}
        try:
            if method == "POST" and path == "/v1/handshake":
                return HTTPStatus.OK, self.runtime.capability_handshake()
            if method == "POST" and path == "/v1/projects":
                return HTTPStatus.OK, self.runtime.init_project(self._required(payload, "project_id"), self._required(payload, "name"))
            if method == "POST" and path == "/v1/routes":
                if self._object(payload, "retrieval_evidence"):
                    return HTTPStatus.CONFLICT, {
                        "status": "retrieval_evidence_rejected",
                        "message": "Route embedding evidence is generated only by LangGraph RAG. Ingest sources through /v1/rag/ingest instead of supplying a success claim.",
                    }
                return HTTPStatus.OK, self.runtime.route_intent(
                    self._required(payload, "project_id"),
                    self._required(payload, "user_input"),
                )
            if method == "POST" and path == "/v1/skills/execute":
                return HTTPStatus.OK, self.runtime.execute_skill(self._required(payload, "skill_id"), self._object(payload, "input"))
            if method == "POST" and path == "/v1/rag/ingest":
                documents = payload.get("documents", [])
                if not isinstance(documents, list):
                    raise AdapterError("documents must be an array")
                return HTTPStatus.OK, self.runtime.rag_store().upsert_documents(
                    str(payload.get("namespace", "pco_rules")),
                    str(payload.get("scope", "product_rule_memory")),
                    documents,
                    str(payload.get("consent_ref", "")),
                )
            if method == "POST" and path == "/v1/rag/bootstrap":
                return HTTPStatus.OK, self.runtime.bootstrap_product_rule_rag()
            if method == "POST" and path == "/v1/rag/retrieve":
                return HTTPStatus.OK, self.runtime.rag_store().retrieve(
                    self._required(payload, "query"),
                    str(payload.get("namespace", "pco_rules")),
                    int(payload.get("top_k", 3)),
                    list(payload.get("allowed_scopes", [])),
                    str(payload.get("consent_ref", "")),
                    str(payload.get("used_for", "host_retrieval")),
                )
            if method == "POST" and path == "/v1/turns":
                route_decision_id = self._required(payload, "route_decision_id")
                if self._object(payload, "skill_execution"):
                    return HTTPStatus.CONFLICT, {
                        "status": "skill_receipt_rejected",
                        "message": "Skill execution receipts are issued only by the LangGraph execute_skill node. Send skill_input instead of a caller-provided success claim.",
                    }
                if self._object(payload, "retrieval_evidence"):
                    return HTTPStatus.CONFLICT, {
                        "status": "retrieval_evidence_rejected",
                        "message": "LangGraph owns route retrieval. Supply sources through /v1/rag/ingest, not retrieval evidence in /v1/turns.",
                    }
                result = self.runtime.run(
                    self._required(payload, "project_id"),
                    self._required(payload, "user_input"),
                    skill_input=self._object(payload, "skill_input"),
                    require_real_embedding=payload.get("require_real_embedding") is True,
                    thread_id=str(payload.get("thread_id") or "") or None,
                    route_decision_id=route_decision_id,
                )
                if result.get("route", {}).get("route_status") == "route_decision_not_found":
                    return HTTPStatus.CONFLICT, result
                return HTTPStatus.OK, result
            if method == "POST" and path == "/v1/reviews/callback":
                return HTTPStatus.OK, self.runtime.resume(self._required(payload, "thread_id"), {"callbacks": list(payload.get("callbacks", []))})
            if method == "POST" and path in {"/v1/review-decisions", "/v1/gates/finalize"}:
                decision = self._object(payload, "decision")
                if path == "/v1/gates/finalize":
                    decision["user_confirmed"] = payload.get("user_confirmed") is True
                    decision["action"] = payload.get("action", decision.get("action", ""))
                return HTTPStatus.OK, self.runtime.resume(self._required(payload, "thread_id"), decision)
            if method == "POST" and path == "/v1/exports/obsidian":
                project_id = self._required(payload, "project_id")
                root = self.runtime.workspace / "projects" / project_id
                return HTTPStatus.OK, {"project_id": project_id, "export_path": str(root), "manifest": str(root / "export-manifest.json")}
            if method == "POST" and path in {"/v1/reviews/prepare", "/v1/review-items", "/v1/skills/host-callback", "/v1/rag/evidence"}:
                return HTTPStatus.CONFLICT, {
                    "status": "use_langgraph_turn_or_resume",
                    "message": "This action is owned by a LangGraph node. Do not write a side-channel record that bypasses the graph.",
                }
            return HTTPStatus.NOT_FOUND, {"error": "unknown_endpoint"}
        except (AdapterError, RuntimeBlocked, ValueError) as error:
            return HTTPStatus.BAD_REQUEST, {"error": str(error), "status": "runtime_blocked"}

    @staticmethod
    def _required(payload: Dict[str, Any], key: str) -> str:
        value = str(payload.get(key, "")).strip()
        if not value:
            raise ValueError(f"{key} is required")
        return value

    @staticmethod
    def _object(payload: Dict[str, Any], key: str) -> Dict[str, Any]:
        value = payload.get(key, {})
        if not isinstance(value, dict):
            raise ValueError(f"{key} must be an object")
        return value


def build_handler(application: BridgeApplication):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            self._dispatch()

        def do_POST(self) -> None:  # noqa: N802
            self._dispatch()

        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def _dispatch(self) -> None:
            if self.path != "/health" and not application.authorize(self.headers.get("Authorization", "")):
                self._respond(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length) if length else b"{}"
                payload = json.loads(raw.decode("utf-8")) if raw else {}
                if not isinstance(payload, dict):
                    raise ValueError("request body must be a JSON object")
            except (ValueError, json.JSONDecodeError) as error:
                self._respond(HTTPStatus.BAD_REQUEST, {"error": f"invalid_json: {error}"})
                return
            status, body = application.handle(self.command, self.path, payload)
            self._respond(status, body)

        def _respond(self, status: int, body: Dict[str, Any]) -> None:
            encoded = json.dumps(body, ensure_ascii=False, default=lambda item: getattr(item, "value", str(item))).encode("utf-8")
            self.send_response(int(status))
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    return Handler


def main() -> int:
    skill_root = Path(__file__).resolve().parent.parent
    workspace = os.environ.get("PCO_RUNTIME_WORKSPACE", str(skill_root / "runtime-workspace"))
    token = os.environ.get("PCO_RUNTIME_TOKEN", "")
    delegate_secret = os.environ.get("PCO_LANGGRAPH_DELEGATE_SECRET", "")
    host = os.environ.get("PCO_RUNTIME_BIND", "127.0.0.1")
    port = int(os.environ.get("PCO_RUNTIME_PORT", "8787"))
    application = BridgeApplication(workspace, skill_root, token, delegate_secret)
    server = ThreadingHTTPServer((host, port), build_handler(application))
    try:
        server.serve_forever()
    finally:
        application.close()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
