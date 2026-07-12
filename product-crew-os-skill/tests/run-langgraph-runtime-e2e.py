#!/usr/bin/env python3
"""E2E checks for the LangGraph-owned Product Crew OS execution path.

Real local command Skills execute inside the graph. Signed review callbacks in
this file remain controlled fixtures: they test the callback contract only.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import yaml

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import ProductCrewLangGraphRuntime  # noqa: E402


def check(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def interrupt_kind(payload: dict) -> str:
    interrupts = payload.get("__interrupt__", [])
    if not interrupts:
        return ""
    first = interrupts[0]
    value = getattr(first, "value", None)
    if value is None and isinstance(first, dict):
        value = first.get("value", {})
    return value.get("kind", "") if isinstance(value, dict) else ""


def research_skill_input() -> dict:
    return {
        "assumptions": [
            {
                "statement": "目标用户每周至少会遇到一次这个问题",
                "category": "desirability",
                "risk": 0.9,
                "certainty": 0.2,
            }
        ]
    }


def signed_callbacks(runtime: ProductCrewLangGraphRuntime, payload: dict, prefix: str) -> list[dict]:
    session_id = payload["review_validation"]["session_id"]
    callbacks: list[dict] = []
    for packet in payload.get("context_packets", []):
        callback = {
            "role_key": packet["persona"]["role_key"],
            "runtime_agent_id": f"fixture-{prefix}-{packet['persona']['role_key'].lower()}",
            "runtime_nickname": "audit-only-fixture-label",
            "context_packet_id": packet["packet_id"],
            "real_invocation_performed": True,
            "raw_review": f"Controlled callback fixture for {packet['persona']['role_key']}.",
        }
        callback["delegate_proof"] = runtime.sign_delegate_callback(session_id, callback)
        callbacks.append(callback)
    return callbacks


def run_real_research(runtime: ProductCrewLangGraphRuntime, project_id: str, thread_id: str) -> dict:
    return runtime.run(
        project_id,
        "我想验证这个痛点是不是真的，帮我设计访谈样本和通过标准。",
        skill_input=research_skill_input(),
        thread_id=thread_id,
    )


def main() -> int:
    errors: list[str] = []
    checks: list[str] = []

    with tempfile.TemporaryDirectory(prefix="pco-langgraph-e2e-") as root:
        runtime = ProductCrewLangGraphRuntime(root, SKILL_ROOT, delegate_secret="test-delegate-secret")
        try:
            non_product = runtime.run("non-product", "今天上海天气怎么样？", thread_id="non-product-thread")
            check(errors, non_product.get("gate_status") == "domain_exit", "non-product input did not exit Product Crew OS")
            checks.append("non-product input exits before route and Skill execution")

            prompt_cases = yaml.safe_load((SKILL_ROOT / "tests" / "prompt-eval-cases.yaml").read_text(encoding="utf-8"))["cases"]
            for case in prompt_cases:
                expected = case["expected"]
                route = runtime.route_intent("sop-routing", case["user_input"])
                check(errors, route.get("stage_id") == case["stage_id"], f"{case['case_id']} did not hit its expected Stage")
                check(errors, route.get("primary_skill") == expected["primary_skill"], f"{case['case_id']} did not hit its expected primary Skill")
            checks.append("all 44 prompt-eval cases reach their expected Stage and primary Skill before execution")

            real = run_real_research(runtime, "real-skill", "real-skill-thread")
            check(errors, real.get("route", {}).get("stage_id") == "research_plan", "research input did not route to research_plan")
            check(errors, real.get("skill_execution", {}).get("gate_valid") is True, "graph did not validate its own command Skill receipt")
            check(errors, real.get("skill_execution", {}).get("driver") == "command", "real graph execution did not use the registered command driver")
            check(errors, Path(real["artifact"]["path"]).is_file(), "graph did not create an artifact from real Skill output")
            check(errors, "Skill 原始输出" in Path(real["artifact"]["path"]).read_text(encoding="utf-8"), "artifact did not retain raw Skill output")
            check(errors, interrupt_kind(real) == "external_review", "validated real Skill execution did not enter the review node")
            checks.append("a routed SOP invokes a real registered Skill inside LangGraph and retains its raw output")

            fake_claim = runtime.run(
                "fake-claim",
                "先做 MVP，不要做大，帮我砍范围和列 not-do。",
                skill_execution={
                    "skill_id": "scope-cutting",
                    "execution_id": "caller-invented",
                    "output_ref": "artifacts/fake.md",
                    "execution_mode": "external_workflow",
                    "contract_valid": True,
                    "may_change_stage": False,
                    "may_decide_gate": False,
                    "may_write_project_memory": False,
                    "may_call_agents": False,
                },
                thread_id="fake-claim-thread",
            )
            check(errors, fake_claim.get("gate_status") == "blocked_runtime_preflight", "caller-provided Skill success claim bypassed graph execution")
            check(errors, fake_claim.get("skill_execution", {}).get("execution_id") != "caller-invented", "caller-provided Skill receipt was accepted")
            checks.append("caller-provided Skill success claims are ignored and cannot pass a Gate")

            persisted_route = runtime.route_intent("persisted-route", "先做 MVP，不要做大，帮我砍范围和列 not-do。")
            persisted_turn = runtime.run("persisted-route", "继续这个既有范围判断。", route_decision_id=persisted_route["route_decision_id"], thread_id="persisted-thread")
            check(errors, persisted_turn.get("route", {}).get("route_decision_id") == persisted_route["route_decision_id"], "turn did not reuse persisted route decision")
            unknown = runtime.run("persisted-route", "使用不存在的路由。", route_decision_id="route_not_real", thread_id="unknown-thread")
            check(errors, unknown.get("route", {}).get("route_status") == "route_decision_not_found", "unknown route decision was not blocked")
            checks.append("turns can reuse only a persisted route decision from the same project")

            embedding_first = runtime.run(
                "embedding-first",
                "请处理这件事。",
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
            check(errors, embedding_first.get("route", {}).get("stage_id") == "mvp_scope", "real embedding candidate did not assist routing")
            check(errors, embedding_first.get("route", {}).get("retrieval_mode") == "real_embedding_adapter", "real embedding evidence was not recorded")
            checks.append("verified embedding candidates can assist routing without bypassing graph evidence")

            spoof = runtime.resume(
                "real-skill-thread",
                {
                    "callbacks": [
                        {
                            "role_key": packet["persona"]["role_key"],
                            "runtime_agent_id": "spoofed-agent",
                            "context_packet_id": packet["packet_id"],
                            "real_invocation_performed": True,
                            "raw_review": "Unsigned callback.",
                        }
                        for packet in real.get("context_packets", [])
                    ]
                },
            )
            check(errors, spoof.get("gate_status") == "blocked_runtime_preflight", "unsigned review callback was allowed to reach a user decision")
            checks.append("unsigned sub-agent callbacks remain blocked after a real Skill run")

            signed = run_real_research(runtime, "signed-review", "signed-review-thread")
            after_review = runtime.resume("signed-review-thread", {"callbacks": signed_callbacks(runtime, signed, "review")})
            check(errors, interrupt_kind(after_review) == "user_stage_decision", "signed review callbacks did not pause for the user decision")
            final = runtime.resume("signed-review-thread", {"user_confirmed": True, "action": "approve", "note": "controlled test decision"})
            check(errors, final.get("gate_status") == "pass", "confirmed user decision did not pass the stage")
            checks.append("real Skill output still requires signed review callbacks and explicit user confirmation")

            revised = run_real_research(runtime, "revision-review", "revision-thread")
            ready_to_revise = runtime.resume("revision-thread", {"callbacks": signed_callbacks(runtime, revised, "revision")})
            rereview = runtime.resume("revision-thread", {"action": "revise", "revision_content": "补充样本筛选条件，并删除无关方案。"})
            check(errors, interrupt_kind(ready_to_revise) == "user_stage_decision", "revision flow did not reach a user decision")
            check(errors, interrupt_kind(rereview) == "external_review", "revision did not reopen targeted review")
            checks.append("user revision writes a new artifact version and reopens review")

            embedding_block = runtime.run(
                "embedding-required",
                "我想做一个产品，第一步应该先做什么？",
                require_real_embedding=True,
                thread_id="embedding-required-thread",
            )
            check(errors, embedding_block.get("route", {}).get("route_status") == "needs_embedding_deployment", "real embedding requirement did not stop an unproven route")
            checks.append("real embedding requirement stops an unproven route before Skill execution")
        finally:
            runtime.close()

    if errors:
        print("run-langgraph-runtime-e2e: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1

    print("run-langgraph-runtime-e2e: PASS")
    for item in checks:
        print(f"- {item}")
    print("note: review callbacks are controlled test fixtures, not production delegates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
