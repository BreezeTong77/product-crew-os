#!/usr/bin/env python3
"""Executable checks for the Python-only runtime adapters and Coze bridge."""

from __future__ import annotations

import sys
import tempfile
import os
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import (  # noqa: E402
    LocalHashDryRunEmbedding,
    PersistentRagStore,
    ProductCrewLangGraphRuntime,
    SkillExecutionAdapter,
    SourceExtractor,
)
from pco_coze_bridge import BridgeApplication  # noqa: E402
from pco_delegate_signer import DelegateSigner  # noqa: E402


def check(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    checks: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pco-python-adapters-") as root:
        root_path = Path(root)
        runtime = ProductCrewLangGraphRuntime(root_path / "runtime", SKILL_ROOT, delegate_secret="adapter-test-secret", rag_provider=LocalHashDryRunEmbedding())
        try:
            runtime.init_project("adapter-project", "Adapter project")
            route = runtime.route_intent("adapter-project", "这个产品怎么定义北极星指标、输入指标和护栏指标？")
            check(errors, route.get("stage_id") == "metrics_design", "Python route-intent did not persist the expected SOP route")
            checks.append("Python route-intent writes a 44-SOP route trace")

            source = root_path / "source.md"
            source.write_text("# Evidence\n\nA structured source for RAG.", encoding="utf-8")
            extracted = SourceExtractor().extract(source, "test:source.md")
            check(errors, extracted.get("extraction_method") == "direct_structured_parser", "Python source extractor did not parse Markdown")
            check(errors, extracted.get("gate_evidence_eligible") is True, "structured source was unexpectedly ineligible")
            checks.append("Python source extractor keeps source hash and gate evidence metadata")

            store = PersistentRagStore(root_path / "rag.sqlite3", provider=LocalHashDryRunEmbedding())
            ingest = store.upsert_documents(
                "pco_rules",
                "product_rule_memory",
                [{"source_ref": "tests/fixture", "title": "MVP", "content": "MVP scope should prove one core hypothesis.", "metadata": {"stage_id": "mvp_scope", "case_id": "fixture"}}],
            )
            retrieved = store.retrieve("MVP scope core hypothesis", top_k=1)
            check(errors, ingest.get("created") == 1, "Python RAG did not create a source document")
            check(errors, retrieved.get("real_embedding_performed") is False, "hash smoke embedding was incorrectly marked real")
            check(errors, retrieved.get("candidates", [{}])[0].get("stage_id") == "mvp_scope", "Python RAG did not return source-bound candidate")
            rebuilt = PersistentRagStore(root_path / "rag.sqlite3", provider=LocalHashDryRunEmbedding(dim=128)).upsert_documents(
                "pco_rules",
                "product_rule_memory",
                [{"source_ref": "tests/fixture", "title": "MVP", "content": "MVP scope should prove one core hypothesis.", "metadata": {"stage_id": "mvp_scope", "case_id": "fixture"}}],
            )
            check(errors, rebuilt.get("updated") == 1, "Python RAG did not rebuild an index after embedding provider dimensions changed")
            checks.append("Python RAG has incremental SQLite storage, rebuilds on embedding changes, and labels hash retrieval as smoke only")

            executor = SkillExecutionAdapter(SKILL_ROOT)
            catalog = executor.catalog_status()
            check(errors, catalog.get("bundled_implementations") == 49, "all 49 bundled Skill implementations were not discovered by the executor")
            skill = executor.execute(
                "product-discovery",
                {"assumptions": [{"statement": "Users have this pain weekly", "category": "desirability", "risk": 0.9, "certainty": 0.2}]},
            )
            check(errors, skill.get("execution_status") == "executed", "Python command Skill did not execute")
            check(errors, skill.get("execution_proof"), "Python command Skill omitted execution proof")
            checks.append("Python Skill adapter discovers all 49 bundled implementations and executes registered command skills")

            bridge = BridgeApplication(root_path / "bridge", SKILL_ROOT, "bridge-token", "bridge-delegate-secret", rag_provider=LocalHashDryRunEmbedding())
            try:
                check(errors, bridge.authorize("Bearer bridge-token"), "Python bridge rejected a correct token")
                check(errors, not bridge.authorize("Bearer wrong"), "Python bridge accepted a wrong token")
                status, bootstrap = bridge.handle("POST", "/v1/rag/bootstrap", {})
                check(errors, int(status) == 200 and bootstrap.get("real_embedding_performed") is False and bootstrap.get("status") == "runtime_blocked", "Python bridge treated hash smoke RAG bootstrap as real")
                status, handshake = bridge.handle("POST", "/v1/handshake", {})
                check(errors, int(status) == 200 and handshake.get("stage_control") == "langgraph", "Python bridge did not report LangGraph control")
                check(errors, handshake.get("standard_sop_status") == "runtime_degraded" and "coze_subagent_bindings" in handshake.get("missing_capabilities", []) and "coze_delegate_signer" in handshake.get("missing_capabilities", []) and "product_rule_rag_index" in handshake.get("missing_capabilities", []), "Python bridge did not expose incomplete standard-SOP deployment")
                bridge.handle("POST", "/v1/projects", {"project_id": "bridge-project", "name": "Bridge project"})
                status, rejected_retrieval = bridge.handle("POST", "/v1/routes", {"project_id": "bridge-project", "user_input": "先做 MVP", "retrieval_evidence": {"real_embedding_performed": True}})
                check(errors, int(status) == 409 and rejected_retrieval.get("status") == "retrieval_evidence_rejected", "Python bridge accepted caller-provided retrieval evidence")
                status, bridge_route = bridge.handle("POST", "/v1/routes", {"project_id": "bridge-project", "user_input": "先做 MVP，不要做大，帮我砍范围和列 not-do。"})
                status, feedback = bridge.handle("POST", "/v1/observability/route-feedback", {"project_id": "bridge-project", "route_decision_id": bridge_route.get("route_decision_id", ""), "outcome": "confirmed", "reason": "Bridge observability coverage"})
                check(errors, int(status) == 200 and feedback.get("outcome") == "confirmed", "Python bridge did not record explicit route feedback")
                status, metrics = bridge.handle("POST", "/v1/observability/metrics", {"project_id": "bridge-project"})
                check(errors, int(status) == 200 and metrics.get("sop_routing", {}).get("confirmed_correct") == 1, "Python bridge did not return evidence-based operational metrics")
                status, bad_cases = bridge.handle("POST", "/v1/observability/bad-cases", {"project_id": "bridge-project"})
                check(errors, int(status) == 200 and isinstance(bad_cases.get("items"), list), "Python bridge did not expose the Bad Case queue")
                bridge_proof = {"skill_id": "scope-cutting", "execution_id": "bridge-proof-001", "output_ref": "artifacts/mvp.md", "execution_mode": "external_workflow", "contract_valid": True, "may_change_stage": False, "may_decide_gate": False, "may_write_project_memory": False, "may_call_agents": False}
                status, rejected = bridge.handle("POST", "/v1/turns", {"project_id": "bridge-project", "user_input": "Continue the persisted MVP route.", "route_decision_id": bridge_route.get("route_decision_id", ""), "skill_execution": bridge_proof, "thread_id": "bridge-rejected-thread"})
                check(errors, int(status) == 409 and rejected.get("status") == "skill_receipt_rejected", "Python bridge accepted a caller-provided Skill receipt")
                status, bridge_turn = bridge.handle("POST", "/v1/turns", {"project_id": "bridge-project", "user_input": "Continue the persisted MVP route.", "route_decision_id": bridge_route.get("route_decision_id", ""), "skill_input": {}, "thread_id": "bridge-thread"})
                check(errors, int(status) == 200 and bridge_turn.get("route", {}).get("route_decision_id") == bridge_route.get("route_decision_id"), "Python bridge did not bind turn to persisted route")
                status, _unknown_turn = bridge.handle("POST", "/v1/turns", {"project_id": "bridge-project", "user_input": "Continue with fake route.", "route_decision_id": "route_unknown", "skill_input": {}, "thread_id": "bridge-thread-unknown"})
                check(errors, int(status) == 409, "Python bridge accepted an unknown route decision")
                status, response = bridge.handle("POST", "/v1/reviews/prepare", {})
                check(errors, int(status) == 409 and response.get("status") == "use_langgraph_turn_or_resume", "Python bridge allowed a side-channel review write")
            finally:
                bridge.close()
            checks.append("Python Coze bridge binds turns to persisted routes, exposes operational metrics, and rejects caller-provided Skill or retrieval receipts")

            bindings_path = root_path / "sub-bot-bindings.private.yaml"
            bindings_path.write_text(
                "bindings:\n  Research:\n    coze_bot_id: bot-research\n    approved_runtime_agent_ids: [agent-research]\n",
                encoding="utf-8",
            )
            previous_bindings = os.environ.get("PCO_SUBAGENT_BINDINGS_PATH")
            os.environ["PCO_SUBAGENT_BINDINGS_PATH"] = str(bindings_path)
            bound_runtime = ProductCrewLangGraphRuntime(root_path / "bound-runtime", SKILL_ROOT, delegate_secret="binding-test-secret", rag_provider=LocalHashDryRunEmbedding())
            try:
                signer = DelegateSigner("signer-test-token", "binding-test-secret", bindings_path)
                binding_status = bound_runtime._subagent_binding_status()
                check(errors, binding_status.get("status") == "bindings_incomplete" and "Tech" in binding_status.get("invalid_roles", []), "Python runtime treated a partial sub-agent binding file as standard-SOP ready")
                state = {
                    "context_packets": [{"packet_id": "ctx-research", "persona": {"role_key": "Research"}}],
                    "review_validation": {"session_id": "review-binding-test"},
                }
                callback = {
                    "role_key": "Research",
                    "runtime_agent_id": "unbound-agent",
                    "context_packet_id": "ctx-research",
                    "coze_invocation_id": "coze-run-research-001",
                    "context_packet_quality": "complete",
                    "persona_injection_status": "complete",
                    "real_invocation_performed": True,
                    "raw_review": "A real-looking review from the wrong bound agent.",
                    "priority": "should_fix",
                }
                try:
                    signer.attest("review-binding-test", callback)
                except ValueError:
                    pass
                else:
                    errors.append("Python delegate signer attested a callback from an unbound runtime agent")
                callback["runtime_agent_id"] = "agent-research"
                attested = signer.attest("review-binding-test", callback)
                validation = bound_runtime._validate_review_callbacks(state, [attested["callback"]])
                check(errors, validation.get("gate_valid") is True, "Python runtime rejected a correctly bound signed callback")
                tampered = dict(attested["callback"])
                tampered["priority"] = "must_fix"
                tampered_validation = bound_runtime._validate_review_callbacks(state, [tampered])
                check(errors, "Research:delegate_proof_invalid" in tampered_validation.get("issues", []), "Python runtime did not detect a signed callback field being changed after attestation")
            finally:
                bound_runtime.close()
                if previous_bindings is None:
                    os.environ.pop("PCO_SUBAGENT_BINDINGS_PATH", None)
                else:
                    os.environ["PCO_SUBAGENT_BINDINGS_PATH"] = previous_bindings
            checks.append("Python delegate signer and review validation reject callbacks from runtime agents outside the configured role binding")
        finally:
            runtime.close()

    if errors:
        print("run-python-runtime-adapters-e2e: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("run-python-runtime-adapters-e2e: PASS")
    for item in checks:
        print(f"- {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
