#!/usr/bin/env python3
"""E2E contract checks for the LangGraph Product Crew OS runtime.

The signed delegate callbacks below are controlled test fixtures. They prove the
adapter contract and must never be described as production sub-agent calls.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import ProductCrewLangGraphRuntime  # noqa: E402


def assert_true(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def skill_proof(skill_id: str, output_ref: str) -> dict:
    return {
        "skill_id": skill_id,
        "execution_id": f"test-exec-{skill_id}",
        "output_ref": output_ref,
        "execution_mode": "native_capability",
        "contract_valid": True,
        "may_change_stage": False,
        "may_decide_gate": False,
        "may_write_project_memory": False,
        "may_call_agents": False,
        "contract_ref": "test:langgraph-runtime-e2e",
    }


def interrupt_kind(payload: dict) -> str:
    interrupts = payload.get("__interrupt__", [])
    if not interrupts:
        return ""
    first = interrupts[0]
    value = getattr(first, "value", None)
    if value is None and isinstance(first, dict):
        value = first.get("value", {})
    return value.get("kind", "") if isinstance(value, dict) else ""


def main() -> int:
    errors: list[str] = []
    checks: list[str] = []

    with tempfile.TemporaryDirectory(prefix="pco-langgraph-e2e-") as root:
        runtime = ProductCrewLangGraphRuntime(root, SKILL_ROOT, delegate_secret="test-delegate-secret")
        try:
            non_product = runtime.run("non-product", "今天上海天气怎么样？", thread_id="non-product-thread")
            assert_true(errors, non_product.get("gate_status") == "domain_exit", "non-product input did not exit Product Crew OS")
            checks.append("non-product input exits before route and skill execution")

            prompt_cases = yaml.safe_load((SKILL_ROOT / "tests" / "prompt-eval-cases.yaml").read_text(encoding="utf-8"))["cases"]
            for case in prompt_cases:
                expected = case["expected"]
                routed = runtime.run(
                    "sop-routing",
                    case["user_input"],
                    skill_execution=skill_proof(expected["primary_skill"], f"artifacts/{case['stage_id']}.md"),
                    thread_id=f"sop-route-{case['stage_id']}",
                )
                assert_true(
                    errors,
                    routed.get("route", {}).get("stage_id") == case["stage_id"],
                    f"{case['case_id']} did not hit its expected stage: {routed.get('route')}",
                )
                assert_true(
                    errors,
                    routed.get("route", {}).get("primary_skill") == expected["primary_skill"],
                    f"{case['case_id']} did not hit its expected primary skill: {routed.get('route')}",
                )
            checks.append("all 44 prompt-eval cases reach their expected Stage and primary Skill through LangGraph")

            persisted_route = runtime.route_intent("persisted-route", "先做 MVP，不要做大，帮我砍范围和列 not-do。")
            routed_turn = runtime.run(
                "persisted-route",
                "This host must use the route decision it already received.",
                skill_execution=skill_proof("scope-cutting", "artifacts/persisted-route.md"),
                route_decision_id=persisted_route["route_decision_id"],
                thread_id="persisted-route-thread",
            )
            assert_true(errors, routed_turn["route"]["route_decision_id"] == persisted_route["route_decision_id"], "turn did not reuse persisted route decision")
            unknown_route = runtime.run(
                "persisted-route",
                "try an unknown route",
                skill_execution=skill_proof("scope-cutting", "artifacts/unknown-route.md"),
                route_decision_id="route_not_real",
                thread_id="unknown-route-thread",
            )
            assert_true(errors, unknown_route.get("route", {}).get("route_status") == "route_decision_not_found", "unknown route decision was not blocked")
            checks.append("turns can reuse only persisted route decisions from the same project")

            embedding_first = runtime.run(
                "embedding-first",
                "请处理这件事。",
                skill_execution=skill_proof("scope-cutting", "artifacts/embedding-first-mvp.md"),
                retrieval_evidence={
                    "real_embedding_performed": True,
                    "provider": "local-bge-adapter",
                    "model": "BAAI/bge-small-zh-v1.5",
                    "source_refs": ["tests/prompt-eval-cases.yaml#S17_mvp_scope"],
                    "candidate_routes": [{"stage_id": "mvp_scope", "score": 0.93}],
                },
                require_real_embedding=True,
                thread_id="embedding-first-thread",
            )
            assert_true(errors, embedding_first["route"]["stage_id"] == "mvp_scope", "real embedding candidate did not assist the input scope gate")
            assert_true(errors, embedding_first["route"]["retrieval_mode"] == "real_embedding_adapter", "real embedding candidate was not recorded as adapter evidence")
            checks.append("verified embedding candidates can assist the input scope gate without bypassing evidence checks")

            missing_skill = runtime.run(
                "missing-skill",
                "我想做一个产品，第一步应该先做什么？",
                thread_id="missing-skill-thread",
            )
            assert_true(errors, missing_skill.get("gate_status") == "blocked_runtime_preflight", "missing skill evidence did not block the gate")
            assert_true(errors, Path(missing_skill["artifact"]["path"]).exists(), "blocked path did not preserve a draft artifact")
            checks.append("missing Skill proof writes a draft but blocks the gate")

            first = runtime.run(
                "review-flow",
                "先做 MVP，不要做大，帮我砍范围和列 not-do。",
                skill_execution=skill_proof("scope-cutting", "artifacts/mvp-scope.md"),
                thread_id="review-thread",
            )
            assert_true(errors, interrupt_kind(first) == "external_review", "MVP flow did not pause for external review")
            packets = first.get("context_packets", [])
            assert_true(errors, any(packet["persona"]["role_key"] == "Biz" for packet in packets), "required Biz packet was not built")
            assert_true(errors, all(packet["context_packet_quality"] == "complete" for packet in packets), "incomplete persona packet reached review interrupt")
            checks.append("validated Skill execution pauses for complete external-review packets")

            spoof = runtime.resume(
                "review-thread",
                {
                    "callbacks": [
                        {
                            "role_key": packet["persona"]["role_key"],
                            "runtime_agent_id": "spoofed-agent",
                            "context_packet_id": packet["packet_id"],
                            "real_invocation_performed": True,
                            "raw_review": "This is intentionally unsigned.",
                        }
                        for packet in packets
                    ]
                },
            )
            assert_true(errors, spoof.get("gate_status") == "blocked_runtime_preflight", "unsigned callback was allowed to reach user decision")
            assert_true(
                errors,
                any("delegate_proof_invalid" in issue for issue in spoof.get("review_validation", {}).get("issues", [])),
                "unsigned callback did not report invalid delegate proof",
            )
            checks.append("spoofed runtime_agent_id without delegate proof is blocked")

            signed_first = runtime.run(
                "signed-review-flow",
                "先做 MVP，不要做大，帮我砍范围和列 not-do。",
                skill_execution=skill_proof("scope-cutting", "artifacts/mvp-scope.md"),
                thread_id="signed-review-thread",
            )
            signed_packets = signed_first.get("context_packets", [])
            session_id = signed_first["review_validation"]["session_id"]
            callbacks = []
            for packet in signed_packets:
                callback = {
                    "role_key": packet["persona"]["role_key"],
                    "runtime_agent_id": f"fixture-delegate-{packet['persona']['role_key'].lower()}",
                    "runtime_nickname": "untrusted-runtime-label",
                    "context_packet_id": packet["packet_id"],
                    "real_invocation_performed": True,
                    "raw_review": f"Controlled fixture callback for {packet['persona']['role_key']}.",
                }
                callback["delegate_proof"] = runtime.sign_delegate_callback(session_id, callback)
                callbacks.append(callback)
            after_review = runtime.resume("signed-review-thread", {"callbacks": callbacks})
            assert_true(errors, interrupt_kind(after_review) == "user_stage_decision", "valid callbacks did not pause for the user decision")
            assert_true(errors, after_review.get("gate_status") != "pass", "review callbacks bypassed user confirmation")
            checks.append("signed callback contract still requires explicit user decision")

            revise_flow = runtime.run(
                "revision-review-flow",
                "先做 MVP，不要做大，帮我砍范围和列 not-do。",
                skill_execution=skill_proof("scope-cutting", "artifacts/mvp-scope.md"),
                thread_id="revision-review-thread",
            )
            revise_packets = revise_flow.get("context_packets", [])
            revise_session_id = revise_flow["review_validation"]["session_id"]
            revise_callbacks = []
            for packet in revise_packets:
                callback = {
                    "role_key": packet["persona"]["role_key"],
                    "runtime_agent_id": f"fixture-revision-{packet['persona']['role_key'].lower()}",
                    "context_packet_id": packet["packet_id"],
                    "real_invocation_performed": True,
                    "raw_review": "Revision fixture review.",
                }
                callback["delegate_proof"] = runtime.sign_delegate_callback(revise_session_id, callback)
                revise_callbacks.append(callback)
            ready_to_revise = runtime.resume("revision-review-thread", {"callbacks": revise_callbacks})
            assert_true(errors, interrupt_kind(ready_to_revise) == "user_stage_decision", "revision flow did not reach a user decision")
            rereview = runtime.resume(
                "revision-review-thread",
                {"action": "revise", "revision_content": "Remove enterprise settings from this MVP and clarify the one core hypothesis."},
            )
            assert_true(errors, interrupt_kind(rereview) == "external_review", "user-requested revision did not reopen focused review")
            assert_true(errors, rereview.get("artifact", {}).get("revision") == 2, "revision did not create a new artifact version")
            assert_true(errors, rereview.get("review_validation", {}).get("session_id") != revise_session_id, "revision reused a closed review session")
            checks.append("user-requested revision writes a new artifact version and reopens external review")

            final = runtime.resume(
                "signed-review-thread",
                {"user_confirmed": True, "action": "approve", "note": "controlled test decision"},
            )
            assert_true(errors, final.get("gate_status") == "pass", "confirmed user decision did not pass the stage gate")
            assert_true(errors, runtime.checkpoint_db.exists(), "SQLite LangGraph checkpoint was not written")
            assert_true(errors, Path(final["artifact"]["path"]).exists(), "final artifact was not retained")
            raw_review = Path(signed_packets[0]["path"]).parents[1] / "raw-review-records" / session_id / f"{signed_packets[0]['persona']['role_key']}.md"
            assert_true(errors, raw_review.exists(), "raw review was not persisted for the callback")
            assert_true(errors, "Runtime nickname (audit only)" in raw_review.read_text(encoding="utf-8"), "runtime nickname was not isolated as audit-only metadata")
            checks.append("same LangGraph checkpoint resumes through review and user confirmation")

            embedding_block = runtime.run(
                "embedding-required",
                "我想做一个产品，第一步应该先做什么？",
                skill_execution=skill_proof("pm-workbench", "artifacts/triage-note.md"),
                require_real_embedding=True,
                thread_id="embedding-required-thread",
            )
            assert_true(errors, embedding_block["route"]["route_status"] == "needs_embedding_deployment", "real embedding requirement did not stop an unproven route")
            checks.append("real embedding requirement stops an unproven route")
        finally:
            runtime.close()

    if errors:
        print("run-langgraph-runtime-e2e: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print("run-langgraph-runtime-e2e: PASS")
    for check in checks:
        print(f"- {check}")
    print("note: signed external review callbacks are controlled test fixtures, not production delegates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
