#!/usr/bin/env python3
"""HTTP contract test for the protected Coze delegate signer."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib import error as urlerror
from urllib import request as urlrequest

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import LocalHashDryRunEmbedding, ProductCrewLangGraphRuntime  # noqa: E402
from pco_delegate_signer import DelegateSigner, SignerApplication, build_handler  # noqa: E402


def post(url: str, token: str, payload: dict) -> tuple[int, dict]:
    request = urlrequest.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlrequest.urlopen(request, timeout=5) as response:  # noqa: S310 - local test server
            return response.status, json.loads(response.read().decode("utf-8"))
    except urlerror.HTTPError as response:
        return response.code, json.loads(response.read().decode("utf-8"))


def main() -> int:
    errors: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pco-delegate-signer-") as root:
        root_path = Path(root)
        bindings = root_path / "sub-bot-bindings.private.yaml"
        bindings.write_text(
            "bindings:\n  Research:\n    coze_bot_id: bot-research\n    approved_runtime_agent_ids: [agent-research]\n",
            encoding="utf-8",
        )
        token = "delegate-signer-test-token"
        secret = "delegate-signer-test-secret"
        application = SignerApplication(DelegateSigner(token, secret, bindings))
        server = ThreadingHTTPServer(("127.0.0.1", 0), build_handler(application))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}"
        old_url = os.environ.get("PCO_DELEGATE_SIGNER_URL")
        old_bindings = os.environ.get("PCO_SUBAGENT_BINDINGS_PATH")
        os.environ["PCO_DELEGATE_SIGNER_URL"] = url
        os.environ["PCO_SUBAGENT_BINDINGS_PATH"] = str(bindings)
        try:
            callback = {
                "role_key": "Research",
                "runtime_agent_id": "agent-research",
                "coze_invocation_id": "coze-invocation-001",
                "context_packet_id": "ctx-research",
                "context_packet_quality": "complete",
                "persona_injection_status": "complete",
                "real_invocation_performed": True,
                "raw_review": "This is an attested real-review callback.",
                "priority": "should_fix",
            }
            status, attested = post(f"{url}/v1/reviews/attest", token, {"session_id": "session-001", "callback": callback})
            if status != 200 or attested.get("status") != "attested" or not attested.get("callback", {}).get("delegate_proof"):
                errors.append("delegate signer did not return an attested callback")
            runtime = ProductCrewLangGraphRuntime(root_path / "runtime", SKILL_ROOT, delegate_secret=secret, rag_provider=LocalHashDryRunEmbedding())
            try:
                signer_status = runtime.capability_handshake().get("delegate_signer", {}).get("status")
                if signer_status != "ready":
                    errors.append("runtime handshake could not reach the delegate signer")
                state = {
                    "context_packets": [{"packet_id": "ctx-research", "persona": {"role_key": "Research"}}],
                    "review_validation": {"session_id": "session-001"},
                }
                validation = runtime._validate_review_callbacks(state, [attested.get("callback", {})])
                if validation.get("gate_valid") is not True:
                    errors.append("runtime did not accept the signer-attested callback")
            finally:
                runtime.close()
            callback["runtime_agent_id"] = "agent-not-bound"
            status, rejected = post(f"{url}/v1/reviews/attest", token, {"session_id": "session-001", "callback": callback})
            if status != 400 or rejected.get("status") != "attestation_rejected":
                errors.append("delegate signer accepted a runtime agent outside its role allow-list")
        finally:
            if old_url is None:
                os.environ.pop("PCO_DELEGATE_SIGNER_URL", None)
            else:
                os.environ["PCO_DELEGATE_SIGNER_URL"] = old_url
            if old_bindings is None:
                os.environ.pop("PCO_SUBAGENT_BINDINGS_PATH", None)
            else:
                os.environ["PCO_SUBAGENT_BINDINGS_PATH"] = old_bindings
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
    if errors:
        print("run-delegate-signer-e2e: FAIL")
        for item in errors:
            print(f"- {item}")
        return 1
    print("run-delegate-signer-e2e: PASS")
    print("- protected signer HTTP endpoint attested a configured Coze callback")
    print("- LangGraph accepted only the signed, role-bound callback")
    print("- signer rejected an unbound runtime agent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
