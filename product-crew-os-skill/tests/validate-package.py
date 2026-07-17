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
    "runtime/pco_delegate_signer.py",
    "runtime/create_demo_vault.py",
    "runtime/requirements-langgraph.txt",
    "runtime/langgraph_runtime/__init__.py",
    "runtime/langgraph_runtime/adapters.py",
    "runtime/langgraph_runtime/delegate_contract.py",
    "runtime/langgraph_runtime/workflow.py",
    "runtime/langgraph_runtime/README.md",
    "references/langgraph-runtime-architecture.md",
    "references/runtime-adapter-contract.md",
    "references/project-intake-guard.md",
    "integrations/coze/runtime-plugin-openapi.yaml",
    "integrations/coze/delegate-signer-openapi.yaml",
    "integrations/coze/workflow-blueprint.yaml",
    "integrations/coze/Dockerfile",
    "integrations/coze/env.example",
    "config/router-calibration.yaml",
    "tests/prompt-eval-cases.yaml",
    "tests/run-langgraph-runtime-e2e.py",
    "tests/run-python-runtime-adapters-e2e.py",
    "tests/run-delegate-signer-e2e.py",
    "tests/run-release-gate.py",
    "tests/run-real-ollama-skill-integration.py",
    "tests/run-real-bge-rag-integration.py",
    "tests/run-standard-sop-readiness-integration.py",
    "tests/run-operational-metrics-e2e.py",
    "tests/check-runtime-dependencies.py",
    "tests/run-host-bridge-acceptance.py",
    "tests/run-project-intake-guard-e2e.py",
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
    for term in ("StateGraph", "SqliteSaver", "interrupt", "Command", "execute_skill", "project_intake_guard", "graph_rag_evidence", "bootstrap_product_rule_rag", "record_route_feedback", "operational_metrics", "langgraph_bad_cases", "runtime_agent_binding_mismatch", "skill_receipt_invalid_or_not_graph_issued", "revise_artifact", "export_project_assets", "PCO_LANGGRAPH_DELEGATE_SECRET"):
        if term not in workflow:
            errors.append(f"LangGraph workflow missing {term}")
    blueprint = yaml.safe_load((ROOT / "integrations" / "coze" / "workflow-blueprint.yaml").read_text(encoding="utf-8"))
    if blueprint.get("deployment_assets", {}).get("runtime_bridge_entrypoint") != "runtime/pco_coze_bridge.py":
        errors.append("Coze blueprint does not point to Python bridge")
    if blueprint.get("deployment_assets", {}).get("delegate_signer_openapi_contract") != "integrations/coze/delegate-signer-openapi.yaml":
        errors.append("Coze blueprint does not point to delegate signer contract")
    dockerfile = (ROOT / "integrations" / "coze" / "Dockerfile").read_text(encoding="utf-8")
    if "pco_coze_bridge.py" not in dockerfile or "ruby" in dockerfile.lower():
        errors.append("Coze Dockerfile still depends on Ruby")
    openapi = yaml.safe_load((ROOT / "integrations" / "coze" / "runtime-plugin-openapi.yaml").read_text(encoding="utf-8"))
    expected_paths = {"/health", "/v1/handshake", "/v1/observability/metrics", "/v1/observability/route-feedback", "/v1/observability/bad-cases", "/v1/projects", "/v1/routes", "/v1/skills/execute", "/v1/rag/ingest", "/v1/rag/bootstrap", "/v1/rag/retrieve", "/v1/turns", "/v1/reviews/callback", "/v1/review-decisions", "/v1/gates/finalize", "/v1/exports/obsidian"}
    missing_paths = expected_paths - set((openapi.get("paths") or {}).keys())
    if missing_paths:
        errors.append("Coze OpenAPI missing Python bridge paths: " + ", ".join(sorted(missing_paths)))
    turn_schema = (((openapi.get("paths") or {}).get("/v1/turns") or {}).get("post") or {}).get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema", {})
    if "skill_input" not in (turn_schema.get("properties") or {}):
        errors.append("Coze OpenAPI turn schema does not accept graph-owned skill_input")
    if "skill_execution" in set(turn_schema.get("required") or []):
        errors.append("Coze OpenAPI still requires caller-provided skill_execution")
    route_schema = (((openapi.get("paths") or {}).get("/v1/routes") or {}).get("post") or {}).get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema", {})
    if "retrieval_evidence" in (route_schema.get("properties") or {}) or "retrieval_evidence" in (turn_schema.get("properties") or {}):
        errors.append("Coze OpenAPI still accepts caller-provided retrieval_evidence")
    signer_openapi = yaml.safe_load((ROOT / "integrations" / "coze" / "delegate-signer-openapi.yaml").read_text(encoding="utf-8"))
    if "/v1/reviews/attest" not in (signer_openapi.get("paths") or {}):
        errors.append("Coze delegate signer OpenAPI is missing attestation endpoint")
    deprecated_runtime_flags = ("PCO_STAGE_ROUTER_EMBEDDING", "PCO_REQUIRE_REAL_EMBEDDING", "PCO_REQUIRE_REAL_SUBAGENTS")
    public_runtime_files = [
        ROOT / "integrations" / "coze" / "Dockerfile",
        ROOT / "integrations" / "coze" / "docker-compose.yml",
        ROOT / "integrations" / "coze" / "workflow-blueprint.yaml",
        ROOT / "references" / "runtime-adapter-contract.md",
    ]
    for path in public_runtime_files:
        content = path.read_text(encoding="utf-8")
        if any(flag in content for flag in deprecated_runtime_flags):
            errors.append(f"public runtime contract contains deprecated inert flags: {path.name}")
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
