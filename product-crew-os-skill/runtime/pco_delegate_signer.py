#!/usr/bin/env python3
"""Trusted callback signer between Coze Call Bot and the LangGraph Bridge.

Coze keeps this service token in its plugin configuration, never in a Bot
prompt. The signer checks the configured role-to-runtime-agent allow-list and
binds the entire callback payload to the review session with HMAC.
"""

from __future__ import annotations

import hmac
import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Tuple

import yaml

from langgraph_runtime.delegate_contract import sign_callback


class DelegateSigner:
    def __init__(self, token: str, delegate_secret: str, bindings_path: str | Path):
        if not token:
            raise ValueError("PCO_DELEGATE_SIGNER_TOKEN is required")
        if not delegate_secret:
            raise ValueError("PCO_LANGGRAPH_DELEGATE_SECRET is required")
        self.token = token
        self.delegate_secret = delegate_secret
        self.bindings_path = Path(bindings_path).expanduser()

    def authorize(self, authorization: str) -> bool:
        return hmac.compare_digest(authorization or "", f"Bearer {self.token}")

    def health(self) -> Dict[str, Any]:
        return {"status": "ok", "service": "pco_delegate_signer", "bindings_path": str(self.bindings_path)}

    def attest(self, session_id: str, callback: Dict[str, Any]) -> Dict[str, Any]:
        callback = dict(callback)
        role_key = str(callback.get("role_key", "")).strip()
        runtime_agent_id = str(callback.get("runtime_agent_id", "")).strip()
        binding = self._bindings().get(role_key, {}) or {}
        allowed = [str(value).strip() for value in binding.get("approved_runtime_agent_ids", []) if str(value).strip()]
        coze_bot_id = str(binding.get("coze_bot_id", "")).strip()
        if not role_key or not binding or not coze_bot_id or "REPLACE_WITH" in coze_bot_id:
            raise ValueError("role_key is not configured in the private sub-agent bindings")
        if not runtime_agent_id or runtime_agent_id not in allowed:
            raise ValueError("runtime_agent_id is not approved for role_key")
        required = ("context_packet_id", "coze_invocation_id", "raw_review")
        missing = [key for key in required if not str(callback.get(key, "")).strip()]
        if missing:
            raise ValueError("callback missing required fields: " + ", ".join(missing))
        if callback.get("real_invocation_performed") is not True:
            raise ValueError("real_invocation_performed must be true")
        if callback.get("context_packet_quality") != "complete" or callback.get("persona_injection_status") != "complete":
            raise ValueError("callback must confirm complete context packet and persona injection")
        if callback.get("simulation_label") or callback.get("result") in {"advice_only", "invalid_for_gate", "simulated", "runtime_blocked"}:
            raise ValueError("simulated or invalid callback cannot be attested")
        callback["delegate_proof"] = sign_callback(self.delegate_secret, session_id, callback)
        return {"status": "attested", "callback": callback}

    def _bindings(self) -> Dict[str, Dict[str, Any]]:
        if not self.bindings_path.is_file():
            raise ValueError("private sub-agent bindings file is missing")
        try:
            payload = yaml.safe_load(self.bindings_path.read_text(encoding="utf-8")) or {}
            bindings = payload.get("bindings", {})
        except (OSError, yaml.YAMLError, AttributeError) as error:
            raise ValueError(f"private sub-agent bindings file is invalid: {error}") from error
        if not isinstance(bindings, dict):
            raise ValueError("private sub-agent bindings must contain a bindings object")
        return bindings


class SignerApplication:
    def __init__(self, signer: DelegateSigner):
        self.signer = signer

    def handle(self, method: str, path: str, payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        if method == "GET" and path == "/health":
            return HTTPStatus.OK, self.signer.health()
        if method == "POST" and path == "/v1/reviews/attest":
            try:
                session_id = str(payload.get("session_id", "")).strip()
                callback = payload.get("callback", {})
                if not session_id or not isinstance(callback, dict):
                    raise ValueError("session_id and callback object are required")
                return HTTPStatus.OK, self.signer.attest(session_id, callback)
            except ValueError as error:
                return HTTPStatus.BAD_REQUEST, {"status": "attestation_rejected", "error": str(error)}
        return HTTPStatus.NOT_FOUND, {"error": "unknown_endpoint"}


def build_handler(application: SignerApplication):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            self._dispatch()

        def do_POST(self) -> None:  # noqa: N802
            self._dispatch()

        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def _dispatch(self) -> None:
            if self.path != "/health" and not application.signer.authorize(self.headers.get("Authorization", "")):
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
            encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(int(status))
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    return Handler


def main() -> int:
    token = os.environ.get("PCO_DELEGATE_SIGNER_TOKEN", "")
    delegate_secret = os.environ.get("PCO_LANGGRAPH_DELEGATE_SECRET", "")
    bindings_path = os.environ.get("PCO_SUBAGENT_BINDINGS_PATH", "")
    host = os.environ.get("PCO_DELEGATE_SIGNER_BIND", "127.0.0.1")
    port = int(os.environ.get("PCO_DELEGATE_SIGNER_PORT", "8788"))
    signer = DelegateSigner(token, delegate_secret, bindings_path)
    server = ThreadingHTTPServer((host, port), build_handler(SignerApplication(signer)))
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
