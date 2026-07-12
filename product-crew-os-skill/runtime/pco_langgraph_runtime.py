#!/usr/bin/env python3
"""CLI entrypoint for the LangGraph Product Crew OS runtime."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from langgraph_runtime import ProductCrewLangGraphRuntime


def as_json(value: Any) -> str:
    def fallback(item: Any) -> Any:
        if hasattr(item, "value"):
            return {"value": item.value, "id": getattr(item, "id", "")}
        return str(item)

    return json.dumps(value, ensure_ascii=False, indent=2, default=fallback)


def parse_json(value: str) -> dict:
    return json.loads(value) if value else {}


def main() -> int:
    parser = argparse.ArgumentParser(description="Product Crew OS LangGraph runtime")
    parser.add_argument("command", choices=["init-project", "run", "resume", "draw-graph"])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--skill-root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--project-id", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--user-input", default="")
    parser.add_argument("--skill-execution-json", default="")
    parser.add_argument("--retrieval-evidence-json", default="")
    parser.add_argument("--require-real-embedding", action="store_true")
    parser.add_argument("--thread-id", default="")
    parser.add_argument("--resume-json", default="")
    parser.add_argument("--output", default="")
    parser.add_argument("--delegate-secret", default="")
    args = parser.parse_args()

    runtime = ProductCrewLangGraphRuntime(args.workspace, args.skill_root, delegate_secret=args.delegate_secret or None)
    try:
        if args.command == "init-project":
            if not args.project_id or not args.name:
                parser.error("init-project requires --project-id and --name")
            result = runtime.init_project(args.project_id, args.name)
        elif args.command == "run":
            if not args.project_id or not args.user_input:
                parser.error("run requires --project-id and --user-input")
            result = runtime.run(
                args.project_id,
                args.user_input,
                skill_execution=parse_json(args.skill_execution_json),
                retrieval_evidence=parse_json(args.retrieval_evidence_json),
                require_real_embedding=args.require_real_embedding,
                thread_id=args.thread_id or None,
            )
        elif args.command == "resume":
            if not args.thread_id or not args.resume_json:
                parser.error("resume requires --thread-id and --resume-json")
            result = runtime.resume(args.thread_id, parse_json(args.resume_json))
        else:
            result = {"mermaid": runtime.draw_mermaid()}
            if args.output:
                Path(args.output).write_text(result["mermaid"], encoding="utf-8")
        print(as_json(result))
    finally:
        runtime.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
