#!/usr/bin/env python3
"""Executable checks for the Python-only runtime adapters and Coze bridge."""

from __future__ import annotations

import sys
import tempfile
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


def check(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    checks: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pco-python-adapters-") as root:
        root_path = Path(root)
        runtime = ProductCrewLangGraphRuntime(root_path / "runtime", SKILL_ROOT, delegate_secret="adapter-test-secret")
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
            checks.append("Python RAG has incremental SQLite storage and labels hash retrieval as smoke only")

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

            bridge = BridgeApplication(root_path / "bridge", SKILL_ROOT, "bridge-token", "bridge-delegate-secret")
            try:
                check(errors, bridge.authorize("Bearer bridge-token"), "Python bridge rejected a correct token")
                check(errors, not bridge.authorize("Bearer wrong"), "Python bridge accepted a wrong token")
                status, handshake = bridge.handle("POST", "/v1/handshake", {})
                check(errors, int(status) == 200 and handshake.get("stage_control") == "langgraph", "Python bridge did not report LangGraph control")
                bridge.handle("POST", "/v1/projects", {"project_id": "bridge-project", "name": "Bridge project"})
                status, bridge_route = bridge.handle("POST", "/v1/routes", {"project_id": "bridge-project", "user_input": "先做 MVP，不要做大，帮我砍范围和列 not-do。"})
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
            checks.append("Python Coze bridge binds turns to persisted routes and rejects caller-provided Skill receipts")
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
