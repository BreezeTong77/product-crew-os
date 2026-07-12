#!/usr/bin/env python3
"""50-case Python/LangGraph release gate: 44 SOP routes plus L45-L50."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runtime"))

from langgraph_runtime import LocalHashDryRunEmbedding, PersistentRagStore, ProductCrewLangGraphRuntime, RuntimeBlocked  # noqa: E402


def proof(skill_id: str) -> dict:
    return {"skill_id": skill_id, "execution_id": f"release-{skill_id}", "output_ref": f"artifacts/{skill_id}.md", "execution_mode": "native_capability", "contract_valid": True, "may_change_stage": False, "may_decide_gate": False, "may_write_project_memory": False, "may_call_agents": False, "contract_ref": "test:release-gate"}


def interrupt_kind(result: dict) -> str:
    values = result.get("__interrupt__", [])
    if not values:
        return ""
    value = getattr(values[0], "value", values[0].get("value", {}) if isinstance(values[0], dict) else {})
    return value.get("kind", "") if isinstance(value, dict) else ""


def signed_callbacks(runtime: ProductCrewLangGraphRuntime, result: dict) -> list[dict]:
    session_id = result["review_validation"]["session_id"]
    callbacks = []
    for packet in result.get("context_packets", []):
        callback = {"role_key": packet["persona"]["role_key"], "runtime_agent_id": f"gate-{packet['persona']['role_key'].lower()}", "runtime_nickname": "audit-only-host-label", "context_packet_id": packet["packet_id"], "real_invocation_performed": True, "raw_review": "Controlled release-gate fixture review."}
        callback["delegate_proof"] = runtime.sign_delegate_callback(session_id, callback)
        callbacks.append(callback)
    return callbacks


def main() -> int:
    errors: list[str] = []
    cases = yaml.safe_load((ROOT / "tests" / "prompt-eval-cases.yaml").read_text(encoding="utf-8"))["cases"]
    with tempfile.TemporaryDirectory(prefix="pco-python-release-") as temp:
        runtime = ProductCrewLangGraphRuntime(temp, ROOT, delegate_secret="release-gate-secret")
        try:
            runtime.init_project("release-gate", "Python release gate")
            for case in cases:
                route = runtime.route_intent("release-gate", case["user_input"])
                expected = case["expected"]
                if route.get("stage_id") != case["stage_id"] or route.get("primary_skill") != expected["primary_skill"]:
                    errors.append(f"{case['case_id']}: expected {case['stage_id']}/{expected['primary_skill']}, got {route.get('stage_id')}/{route.get('primary_skill')}")

            non_product = runtime.run("release-gate", "今天上海天气怎么样？", thread_id="l45")
            if non_product.get("gate_status") != "domain_exit":
                errors.append("L45 non-product request entered Product Crew OS")

            review = runtime.run("release-gate", "先做 MVP，不要做大，帮我砍范围和列 not-do。", skill_execution=proof("scope-cutting"), thread_id="l46-l47")
            callbacks = signed_callbacks(runtime, review)
            after_review = runtime.resume("l46-l47", {"callbacks": callbacks})
            raw_review = Path(review["context_packets"][0]["path"]).parents[1] / "raw-review-records" / review["review_validation"]["session_id"] / f"{review['context_packets'][0]['persona']['role_key']}.md"
            if interrupt_kind(after_review) != "user_stage_decision":
                errors.append("L46/L47 valid callback did not reach user decision")
            if not raw_review.exists() or "Runtime nickname (audit only)" not in raw_review.read_text(encoding="utf-8"):
                errors.append("L46/L47 nickname isolation or raw review visibility failed")

            store = PersistentRagStore(Path(temp) / "private-rag.sqlite3", provider=LocalHashDryRunEmbedding())
            try:
                store.upsert_documents("project_private", "project_memory", [{"source_ref": "private:test", "title": "private", "content": "private"}])
                errors.append("L48 private RAG write accepted without consent")
            except RuntimeBlocked:
                pass

            pending = runtime.resume("l46-l47", {"action": "defer"})
            if pending.get("gate_status") == "pass":
                errors.append("L50 user defer incorrectly passed the gate")
            manifest = Path(temp) / "projects" / "release-gate" / "export-manifest.json"
            if not manifest.exists():
                errors.append("L49 project asset export was not written")
        finally:
            runtime.close()
    if errors:
        print("run-release-gate: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("run-release-gate: PASS")
    print("cases: 50 (44 SOP routing controls + L45-L50 runtime boundaries)")
    print("note: 44 SOP route cases do not claim real Skill or external delegate execution")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
