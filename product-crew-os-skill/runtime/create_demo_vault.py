#!/usr/bin/env python3
"""Create an Obsidian-readable LangGraph runtime demo without fake Skill success."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

from langgraph_runtime import ProductCrewLangGraphRuntime


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a Product Crew OS LangGraph demo project")
    parser.add_argument("--output-dir", default="runtime-demo-vault")
    parser.add_argument("--project-id", default="runtime-demo")
    parser.add_argument("--project-name", default="Product Crew OS Runtime Demo")
    parser.add_argument("--limit", type=int, default=44)
    args = parser.parse_args()

    skill_root = Path(__file__).resolve().parent.parent
    output = Path(args.output_dir).expanduser().resolve()
    workspace = output / "workspace"
    runtime = ProductCrewLangGraphRuntime(workspace, skill_root)
    try:
        runtime.init_project(args.project_id, args.project_name)
        cases = yaml.safe_load((skill_root / "tests" / "prompt-eval-cases.yaml").read_text(encoding="utf-8"))["cases"][: args.limit]
        results = []
        for case in cases:
            result = runtime.run(args.project_id, case["user_input"], thread_id=f"demo-{case['stage_id']}")
            results.append({"case_id": case["case_id"], "stage_id": result.get("route", {}).get("stage_id"), "gate_status": result.get("gate_status")})
        project_root = workspace / "projects" / args.project_id
        summary = {
            "project_id": args.project_id,
            "project_name": args.project_name,
            "workspace": str(workspace),
            "project_package": str(project_root),
            "cases": results,
            "notice": "Demo artifacts are deliberately draft_not_gate_valid unless a real Skill execution receipt and real review callbacks are provided.",
        }
        (output / "demo-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    finally:
        runtime.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
