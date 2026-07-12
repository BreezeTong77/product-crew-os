#!/usr/bin/env python3
"""E2E coverage for evidence-based Product Crew OS operational metrics.

The route feedback and review callbacks are controlled test inputs. The Skill is
executed by the real registered command driver inside LangGraph.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import LocalHashDryRunEmbedding, ProductCrewLangGraphRuntime  # noqa: E402


def interrupt_value(payload: dict) -> dict:
    item = (payload.get("__interrupt__") or [{}])[0]
    return getattr(item, "value", item.get("value", {}) if isinstance(item, dict) else {})


def signed_callbacks(runtime: ProductCrewLangGraphRuntime, payload: dict) -> list[dict]:
    session_id = payload["review_validation"]["session_id"]
    callbacks = []
    for packet in payload.get("context_packets", []):
        callback = {
            "role_key": packet["persona"]["role_key"],
            "runtime_agent_id": f"metric-fixture-{packet['persona']['role_key'].lower()}",
            "context_packet_id": packet["packet_id"],
            "real_invocation_performed": True,
            "raw_review": "Controlled callback for operational-metrics coverage.",
        }
        callback["delegate_proof"] = runtime.sign_delegate_callback(session_id, callback)
        callbacks.append(callback)
    return callbacks


def main() -> int:
    errors: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pco-operational-metrics-") as root:
        runtime = ProductCrewLangGraphRuntime(root, SKILL_ROOT, delegate_secret="operational-metrics-secret", rag_provider=LocalHashDryRunEmbedding())
        try:
            project_id = "metrics-project"
            runtime.init_project(project_id, "Operational metrics")
            first = runtime.route_intent(project_id, "先做 MVP，不要做大，帮我砍范围和列 not-do。")
            runtime.record_route_feedback(project_id, first["route_decision_id"], "confirmed", reason="用户确认当前先做范围收敛")
            for _ in range(3):
                route = runtime.route_intent(project_id, "先做 MVP，不要做大，帮我砍范围和列 not-do。")
                runtime.record_route_feedback(
                    project_id,
                    route["route_decision_id"],
                    "corrected",
                    corrected_stage_id="research_plan",
                    reason="测试同类错误进入人工调参队列",
                )

            run = runtime.run(
                project_id,
                "我想验证这个痛点是不是真的，帮我设计访谈样本和通过标准。",
                skill_input={"assumptions": [{"statement": "目标用户每周遇到一次问题", "category": "desirability", "risk": 0.9, "certainty": 0.2}]},
                thread_id="operational-metrics-thread",
            )
            if run.get("skill_execution", {}).get("gate_valid") is not True:
                errors.append("real command Skill did not reach a graph-valid execution receipt")
            callbacks = signed_callbacks(runtime, run)
            reviewed = runtime.resume("operational-metrics-thread", {"callbacks": callbacks})
            if interrupt_value(reviewed).get("kind") != "user_stage_decision":
                errors.append("review callbacks did not complete the review session")

            metrics = runtime.operational_metrics(project_id)
            routing = metrics["sop_routing"]
            skill = metrics["skill_execution"]
            agent = metrics["subagent_feedback"]
            if routing["evaluated_by_human"] != 4 or routing["confirmed_correct"] != 1 or routing["corrected"] != 3:
                errors.append(f"SOP metrics were incorrect: {routing}")
            if not metrics["calibration_review_queue"]:
                errors.append("repeated corrected routes did not create a pending human calibration recommendation")
            if skill["signed_graph_executions"] < 1 or skill["true_execution_rate"] is None:
                errors.append(f"Skill true-execution metrics were incorrect: {skill}")
            if agent["expected_callback_slots"] != len(callbacks) or agent["valid_callback_slots"] != len(callbacks):
                errors.append(f"sub-agent callback metrics were incorrect: {agent}")
            if agent["real_callback_completion_rate"] != 1.0:
                errors.append(f"sub-agent completion rate was not 1.0: {agent}")
            if metrics["bad_cases"]["by_category"].get("sop_route_correction") != 3:
                errors.append(f"route corrections were not stored as Bad Cases: {metrics['bad_cases']}")
            paths = metrics.get("artifact_paths", {})
            if not Path(paths.get("json", "")).is_file() or not Path(paths.get("markdown", "")).is_file():
                errors.append("operational metrics were not exported to the project vault")
        finally:
            runtime.close()
    if errors:
        print("run-operational-metrics-e2e: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("run-operational-metrics-e2e: PASS")
    print("- human-confirmed SOP accuracy excludes unverified routes")
    print("- graph-issued Skill receipts drive true-execution rate")
    print("- valid review callbacks drive sub-agent completion rate")
    print("- repeated route corrections create Bad Cases and a human-only calibration recommendation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
