#!/usr/bin/env python3
"""Real integration test for graph-owned local BGE SOP retrieval.

This test intentionally fails if the BGE package or model is unavailable. It
must never turn lexical fallback or hash smoke vectors into a passing result.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_ROOT / "runtime"))

from langgraph_runtime import ProductCrewLangGraphRuntime  # noqa: E402


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="pco-real-bge-") as workspace:
        runtime = ProductCrewLangGraphRuntime(workspace, SKILL_ROOT)
        try:
            bootstrap = runtime.bootstrap_product_rule_rag()
            handshake = runtime.capability_handshake()
            route = runtime.route_intent("real-bge", "我想验证这个痛点是不是真的，帮我设计访谈样本和通过标准。")
            errors: list[str] = []
            if bootstrap.get("status") != "ready" or bootstrap.get("real_embedding_performed") is not True:
                errors.append(f"BGE bootstrap did not complete: {bootstrap}")
            if handshake.get("embedding", {}).get("index_status") != "ready" or "product_rule_rag_index" in handshake.get("missing_capabilities", []):
                errors.append(f"Handshake did not recognize the real SOP RAG index: {handshake.get('embedding')}")
            if route.get("real_embedding_performed") is not True:
                errors.append(f"BGE did not execute: {route.get('embedding_status')}")
            if route.get("evidence_retrieval_mode") != "graph_rag_real_embedding":
                errors.append(f"Graph did not record real RAG retrieval: {route.get('evidence_retrieval_mode')}")
            if not route.get("candidate_routes"):
                errors.append("real RAG did not return SOP candidates")
            stats = runtime.rag_store().stats()
            if stats.get("documents") != 44 or stats.get("chunks", 0) < 44:
                errors.append(f"SOP RAG index is incomplete: {stats}")
            if errors:
                print("run-real-bge-rag-integration: FAIL")
                for error in errors:
                    print(f"- {error}")
                return 1
        finally:
            runtime.close()

    print("run-real-bge-rag-integration: PASS")
    print("evidence: 44 SOP documents indexed with local BGE; graph-owned retrieval returned route candidates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
