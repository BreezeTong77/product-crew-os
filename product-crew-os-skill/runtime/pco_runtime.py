#!/usr/bin/env python3
"""Python-only Product Crew OS runtime CLI.

All stage control is delegated to ProductCrewLangGraphRuntime. This CLI is an
adapter boundary for hosts, OCR/RAG and Skill execution; it cannot bypass the
LangGraph Stage Gate.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict

from langgraph_runtime import ProductCrewLangGraphRuntime, SourceExtractor


def parse_json(value: str, label: str) -> Dict[str, Any]:
    if not value:
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as error:
        raise SystemExit(f"{label} must be valid JSON: {error.msg}") from error
    if not isinstance(parsed, dict):
        raise SystemExit(f"{label} must be a JSON object")
    return parsed


def render(value: Any) -> str:
    def fallback(item: Any) -> Any:
        if hasattr(item, "value"):
            return {"value": item.value, "id": getattr(item, "id", "")}
        return str(item)

    return json.dumps(value, ensure_ascii=False, indent=2, default=fallback)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Product Crew OS Python + LangGraph runtime")
    result.add_argument(
        "command",
        choices=[
            "health",
            "capability-handshake",
            "operational-metrics",
            "record-route-feedback",
            "list-bad-cases",
            "init-project",
            "route-intent",
            "execute-skill",
            "rag-ingest",
            "rag-bootstrap",
            "rag-retrieve",
            "source-extract",
            "record-turn",
            "resume",
            "draw-graph",
            "export-obsidian",
        ],
    )
    result.add_argument("--workspace", required=True)
    result.add_argument("--skill-root", default=str(Path(__file__).resolve().parent.parent))
    result.add_argument("--project-id", default="")
    result.add_argument("--name", default="")
    result.add_argument("--user-input", default="")
    result.add_argument("--thread-id", default="")
    result.add_argument("--route-decision-id", default="")
    result.add_argument("--feedback-outcome", default="")
    result.add_argument("--corrected-stage-id", default="")
    result.add_argument("--reason", default="")
    result.add_argument("--feedback-source", default="user")
    result.add_argument("--bad-case-status", default="open")
    result.add_argument("--skill-id", default="")
    result.add_argument("--input-json", default="{}")
    result.add_argument("--skill-input-json", default="{}")
    result.add_argument("--skill-execution-json", default="{}")
    result.add_argument("--retrieval-evidence-json", default="{}")
    result.add_argument("--resume-json", default="{}")
    result.add_argument("--documents-json", default="[]")
    result.add_argument("--namespace", default="pco_rules")
    result.add_argument("--scope", default="product_rule_memory")
    result.add_argument("--consent-ref", default="")
    result.add_argument("--query", default="")
    result.add_argument("--top-k", type=int, default=3)
    result.add_argument("--file-path", default="")
    result.add_argument("--source-ref", default="")
    result.add_argument("--source-type", default="auto")
    result.add_argument("--language-hint", default="chi_sim+eng")
    result.add_argument("--require-real-embedding", action="store_true")
    result.add_argument("--delegate-secret", default="")
    result.add_argument("--output", default="")
    return result


def main() -> int:
    args = parser().parse_args()
    runtime = ProductCrewLangGraphRuntime(args.workspace, args.skill_root, delegate_secret=args.delegate_secret or None)
    try:
        if args.command == "health":
            result: Any = {"status": "ok", "runtime": "python_langgraph", "workspace": str(Path(args.workspace).resolve())}
        elif args.command == "capability-handshake":
            result = runtime.capability_handshake()
        elif args.command == "operational-metrics":
            if not args.project_id:
                raise SystemExit("operational-metrics requires --project-id")
            result = runtime.operational_metrics(args.project_id)
        elif args.command == "record-route-feedback":
            if not args.project_id or not args.route_decision_id or not args.feedback_outcome:
                raise SystemExit("record-route-feedback requires --project-id, --route-decision-id and --feedback-outcome")
            result = runtime.record_route_feedback(
                args.project_id,
                args.route_decision_id,
                args.feedback_outcome,
                args.corrected_stage_id,
                args.reason,
                args.feedback_source,
            )
        elif args.command == "list-bad-cases":
            if not args.project_id:
                raise SystemExit("list-bad-cases requires --project-id")
            result = runtime.list_bad_cases(args.project_id, args.bad_case_status)
        elif args.command == "init-project":
            if not args.project_id or not args.name:
                raise SystemExit("init-project requires --project-id and --name")
            result = runtime.init_project(args.project_id, args.name)
        elif args.command == "route-intent":
            if not args.project_id or not args.user_input:
                raise SystemExit("route-intent requires --project-id and --user-input")
            if parse_json(args.retrieval_evidence_json, "--retrieval-evidence-json"):
                raise SystemExit("route-intent rejects --retrieval-evidence-json; ingest sources and let LangGraph RAG build route evidence")
            result = runtime.route_intent(args.project_id, args.user_input)
        elif args.command == "execute-skill":
            if not args.skill_id:
                raise SystemExit("execute-skill requires --skill-id")
            result = runtime.execute_skill(args.skill_id, parse_json(args.input_json, "--input-json"))
        elif args.command == "rag-ingest":
            try:
                documents = json.loads(args.documents_json)
            except json.JSONDecodeError as error:
                raise SystemExit(f"--documents-json must be valid JSON: {error.msg}") from error
            if not isinstance(documents, list):
                raise SystemExit("--documents-json must be a JSON array")
            result = runtime.rag_store().upsert_documents(args.namespace, args.scope, documents, args.consent_ref)
        elif args.command == "rag-bootstrap":
            result = runtime.bootstrap_product_rule_rag()
        elif args.command == "rag-retrieve":
            if not args.query:
                raise SystemExit("rag-retrieve requires --query")
            result = runtime.rag_store().retrieve(args.query, args.namespace, args.top_k, consent_ref=args.consent_ref)
        elif args.command == "source-extract":
            if not args.file_path or not args.source_ref:
                raise SystemExit("source-extract requires --file-path and --source-ref")
            result = SourceExtractor().extract(args.file_path, args.source_ref, args.source_type, args.language_hint)
        elif args.command == "record-turn":
            if not args.project_id or not args.user_input:
                raise SystemExit("record-turn requires --project-id and --user-input")
            legacy_execution = parse_json(args.skill_execution_json, "--skill-execution-json")
            if legacy_execution:
                raise SystemExit("record-turn rejects --skill-execution-json; send bounded --skill-input-json and let LangGraph execute the routed Skill")
            legacy_retrieval = parse_json(args.retrieval_evidence_json, "--retrieval-evidence-json")
            if legacy_retrieval:
                raise SystemExit("record-turn rejects --retrieval-evidence-json; ingest sources and let LangGraph RAG build route evidence")
            result = runtime.run(
                args.project_id,
                args.user_input,
                skill_input=parse_json(args.skill_input_json, "--skill-input-json"),
                require_real_embedding=args.require_real_embedding,
                thread_id=args.thread_id or None,
                route_decision_id=args.route_decision_id,
            )
        elif args.command == "resume":
            if not args.thread_id:
                raise SystemExit("resume requires --thread-id")
            result = runtime.resume(args.thread_id, parse_json(args.resume_json, "--resume-json"))
        elif args.command == "draw-graph":
            result = {"mermaid": runtime.draw_mermaid()}
        else:
            if not args.project_id:
                raise SystemExit("export-obsidian requires --project-id")
            root = Path(args.workspace).resolve() / "projects" / args.project_id
            manifest = root / "export-manifest.json"
            result = {"project_id": args.project_id, "export_path": str(root), "manifest": str(manifest), "status": "exported" if manifest.exists() else "no_completed_stage_export"}
        if args.output:
            Path(args.output).write_text(render(result), encoding="utf-8")
        print(render(result))
        return 0
    finally:
        runtime.close()


if __name__ == "__main__":
    raise SystemExit(main())
