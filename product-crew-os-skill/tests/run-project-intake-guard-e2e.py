#!/usr/bin/env python3
"""Regression for BC-INTAKE-001: a one-line idea must stay an intake draft."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import LocalHashDryRunEmbedding, ProductCrewLangGraphRuntime  # noqa: E402


def check(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    with tempfile.TemporaryDirectory(prefix="pco-intake-guard-") as root:
        runtime = ProductCrewLangGraphRuntime(root, SKILL_ROOT, rag_provider=LocalHashDryRunEmbedding())
        try:
            result = runtime.run(
                "viral-personality",
                "我现在想做一个爆款人格测试产品，类似 SBTI。",
                thread_id="intake-guard-thread",
            )
            route = result.get("route", {})
            guard = result.get("intake_guard", {})
            check(errors, route.get("stage_id") == "project_intake", "viral idea did not route to project_intake")
            check(errors, route.get("macro_stage") == "opportunity_discovery", "macro stage was not kept separate")
            check(errors, "Biz" in route.get("triggered_roles", []), "viral business signal did not trigger Biz")
            check(errors, guard.get("status") == "needs_clarification", "one-line idea incorrectly passed the intake guard")
            check(errors, "target_user_missing" in guard.get("unknowns", []), "missing target user was not recorded")
            check(errors, "success_definition_missing" in guard.get("unknowns", []), "vague viral goal was treated as a success definition")
            check(errors, "demand_authenticity_score" in guard.get("forbidden_until_evidence", []), "unsupported demand score was not forbidden")
            trace = Path(root) / "projects" / "viral-personality" / "routing" / "stage-route-decision.jsonl"
            check(errors, trace.is_file(), "project intake did not write a route trace")
            artifact = Path(result.get("artifact", {}).get("path", ""))
            check(errors, artifact.is_file(), "project intake did not create a traceable draft artifact")
            if artifact.is_file():
                content = artifact.read_text(encoding="utf-8")
                check(errors, "## 项目接入边界" in content, "intake artifact omitted fact and assumption boundary")
                check(errors, "demand_authenticity_score" in content, "intake artifact omitted forbidden early decisions")
        finally:
            runtime.close()
    if errors:
        print("run-project-intake-guard-e2e: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("run-project-intake-guard-e2e: PASS")
    print("BC-INTAKE-001: one-line idea remains project_intake with trace, assumptions, gaps, and Biz trigger")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
