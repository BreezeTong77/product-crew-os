#!/usr/bin/env python3
"""Real integration test: LangGraph runs a bundled Skill through local Ollama.

This is intentionally not a mock. It fails when Ollama or the configured model
is unavailable, rather than marking a deployment gap as a passing test.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import ProductCrewLangGraphRuntime  # noqa: E402


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="pco-real-ollama-") as workspace:
        runtime = ProductCrewLangGraphRuntime(workspace, SKILL_ROOT, delegate_secret="real-ollama-test-secret")
        try:
            result = runtime.run(
                "real-ollama-mvp",
                "先做 MVP，不要做大，帮我砍范围和列 not-do。",
                thread_id="real-ollama-mvp-thread",
            )
            execution = result.get("skill_execution", {})
            artifact = result.get("artifact", {})
            errors: list[str] = []
            if execution.get("execution_status") != "executed":
                errors.append(f"Skill was not executed: {execution.get('deployment_notice') or execution.get('detail')}")
            if execution.get("driver") != "ollama_prompt":
                errors.append(f"Expected ollama_prompt, got {execution.get('driver')}")
            if execution.get("skill_id") != "scope-cutting":
                errors.append(f"Expected primary scope-cutting, got {execution.get('skill_id')}")
            if execution.get("gate_valid") is not True:
                errors.append("LangGraph did not validate the graph-issued Skill receipt")
            if not artifact.get("path") or not Path(artifact["path"]).is_file():
                errors.append("Artifact from real Ollama Skill output was not saved")
            research = runtime.run(
                "real-ollama-research",
                "我想验证这个痛点是不是真的，帮我设计访谈样本和通过标准。",
                thread_id="real-ollama-research-thread",
            )
            research_execution = research.get("skill_execution", {})
            if research_execution.get("skill_id") != "product-discovery" or research_execution.get("driver") != "ollama_prompt":
                errors.append("unstructured product-discovery did not fall back from its command helper to its own bundled Skill")
            if research_execution.get("execution_proof", {}).get("prior_attempt", {}).get("driver") != "command":
                errors.append("product-discovery did not record the failed command-helper attempt before model execution")
            if errors:
                print("run-real-ollama-skill-integration: FAIL")
                for error in errors:
                    print(f"- {error}")
                return 1
        finally:
            runtime.close()

    print("run-real-ollama-skill-integration: PASS")
    print("evidence: mvp_scope -> scope-cutting executed by local Ollama; research_plan -> product-discovery command helper fallback -> same bundled Skill via Ollama; both receive graph-issued receipts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
