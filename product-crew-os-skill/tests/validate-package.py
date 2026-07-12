#!/usr/bin/env python3
"""Static validation for the Python-only LangGraph release package."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "SKILL.md",
    "runtime/pco_runtime.py",
    "runtime/pco_coze_bridge.py",
    "runtime/create_demo_vault.py",
    "runtime/requirements-langgraph.txt",
    "runtime/langgraph_runtime/__init__.py",
    "runtime/langgraph_runtime/adapters.py",
    "runtime/langgraph_runtime/workflow.py",
    "runtime/langgraph_runtime/README.md",
    "references/langgraph-runtime-architecture.md",
    "references/runtime-adapter-contract.md",
    "integrations/coze/runtime-plugin-openapi.yaml",
    "integrations/coze/workflow-blueprint.yaml",
    "integrations/coze/Dockerfile",
    "tests/prompt-eval-cases.yaml",
    "tests/run-langgraph-runtime-e2e.py",
    "tests/run-python-runtime-adapters-e2e.py",
    "tests/run-release-gate.py",
]


def main() -> int:
    errors: list[str] = []
    for path in ROOT.rglob("*.yaml"):
        try:
            yaml.safe_load(path.read_text(encoding="utf-8"))
        except yaml.YAMLError as error:
            errors.append(f"YAML parse failed: {path.relative_to(ROOT)}: {error}")
    for path in ROOT.rglob("*.json"):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            errors.append(f"JSON parse failed: {path.relative_to(ROOT)}: {error}")
    for relative in REQUIRED:
        if not (ROOT / relative).is_file():
            errors.append(f"Missing required file: {relative}")
    runtime_ruby = list((ROOT / "runtime").glob("*.rb"))
    if runtime_ruby:
        errors.append("Ruby runtime files remain: " + ", ".join(path.name for path in runtime_ruby))
    workflow = (ROOT / "runtime" / "langgraph_runtime" / "workflow.py").read_text(encoding="utf-8")
    for term in ("StateGraph", "SqliteSaver", "interrupt", "Command", "revise_artifact", "export_project_assets", "PCO_LANGGRAPH_DELEGATE_SECRET"):
        if term not in workflow:
            errors.append(f"LangGraph workflow missing {term}")
    blueprint = yaml.safe_load((ROOT / "integrations" / "coze" / "workflow-blueprint.yaml").read_text(encoding="utf-8"))
    if blueprint.get("deployment_assets", {}).get("runtime_bridge_entrypoint") != "runtime/pco_coze_bridge.py":
        errors.append("Coze blueprint does not point to Python bridge")
    dockerfile = (ROOT / "integrations" / "coze" / "Dockerfile").read_text(encoding="utf-8")
    if "pco_coze_bridge.py" not in dockerfile or "ruby" in dockerfile.lower():
        errors.append("Coze Dockerfile still depends on Ruby")
    openapi = yaml.safe_load((ROOT / "integrations" / "coze" / "runtime-plugin-openapi.yaml").read_text(encoding="utf-8"))
    expected_paths = {"/health", "/v1/handshake", "/v1/projects", "/v1/routes", "/v1/skills/execute", "/v1/rag/ingest", "/v1/rag/retrieve", "/v1/turns", "/v1/reviews/callback", "/v1/review-decisions", "/v1/gates/finalize", "/v1/exports/obsidian"}
    missing_paths = expected_paths - set((openapi.get("paths") or {}).keys())
    if missing_paths:
        errors.append("Coze OpenAPI missing Python bridge paths: " + ", ".join(sorted(missing_paths)))
    if errors:
        print("validate-package: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    cases = yaml.safe_load((ROOT / "tests" / "prompt-eval-cases.yaml").read_text(encoding="utf-8"))["cases"]
    print("validate-package: PASS")
    print(f"prompt-eval cases: {len(cases)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
