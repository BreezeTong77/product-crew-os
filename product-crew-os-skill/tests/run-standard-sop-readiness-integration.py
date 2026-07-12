#!/usr/bin/env python3
"""Real local readiness test for the standard-SOP deployment handshake.

It uses temporary test role IDs and a local signer only. It proves local BGE,
Ollama, the full role binding contract and signer health can turn the handshake
ready; it does not claim that real Coze Bots have been deployed.
"""

from __future__ import annotations

import os
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import ProductCrewLangGraphRuntime  # noqa: E402
from pco_delegate_signer import DelegateSigner, SignerApplication, build_handler  # noqa: E402


def main() -> int:
    errors: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pco-standard-readiness-") as root:
        root_path = Path(root)
        personas = yaml.safe_load((SKILL_ROOT / "config" / "crew-personas.yaml").read_text(encoding="utf-8"))
        roles = sorted(
            str(persona["role_key"])
            for persona in personas.get("personas", {}).values()
            if str(persona.get("role_key", "")) != "Coach"
        )
        bindings = {
            role: {
                "coze_bot_id": f"test-bot-{role.lower()}",
                "approved_runtime_agent_ids": [f"test-agent-{role.lower()}"],
            }
            for role in roles
        }
        bindings_path = root_path / "sub-bot-bindings.private.yaml"
        bindings_path.write_text(yaml.safe_dump({"bindings": bindings}, sort_keys=False), encoding="utf-8")
        signer = DelegateSigner("readiness-signer-token", "readiness-delegate-secret", bindings_path)
        server = ThreadingHTTPServer(("127.0.0.1", 0), build_handler(SignerApplication(signer)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        prior = {
            "PCO_SUBAGENT_BINDINGS_PATH": os.environ.get("PCO_SUBAGENT_BINDINGS_PATH"),
            "PCO_DELEGATE_SIGNER_URL": os.environ.get("PCO_DELEGATE_SIGNER_URL"),
        }
        os.environ["PCO_SUBAGENT_BINDINGS_PATH"] = str(bindings_path)
        os.environ["PCO_DELEGATE_SIGNER_URL"] = f"http://127.0.0.1:{server.server_port}"
        runtime = ProductCrewLangGraphRuntime(root_path / "runtime", SKILL_ROOT, delegate_secret="readiness-delegate-secret")
        try:
            bootstrap = runtime.bootstrap_product_rule_rag()
            handshake = runtime.capability_handshake()
            if bootstrap.get("status") != "ready" or bootstrap.get("real_embedding_performed") is not True:
                errors.append(f"real BGE bootstrap did not complete: {bootstrap}")
            if handshake.get("standard_sop_status") != "ready_for_standard_sop":
                errors.append(f"handshake remained degraded: {handshake.get('missing_capabilities', [])}")
            if handshake.get("subagent_dispatch", {}).get("status") != "bindings_declared":
                errors.append("complete temporary role bindings were not accepted")
            if handshake.get("delegate_signer", {}).get("status") != "ready":
                errors.append("delegate signer was not reachable from capability handshake")
        finally:
            runtime.close()
            for key, value in prior.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
    if errors:
        print("run-standard-sop-readiness-integration: FAIL")
        for item in errors:
            print(f"- {item}")
        return 1
    print("run-standard-sop-readiness-integration: PASS")
    print("evidence: local BGE, Ollama, full role bindings and Delegate Signer satisfied the standard-SOP handshake")
    print("boundary: temporary binding IDs prove deployment readiness only, not real Coze Bot invocation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
