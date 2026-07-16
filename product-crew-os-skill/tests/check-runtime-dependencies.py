#!/usr/bin/env python3
"""Fail early when the local Python runtime cannot start Product Crew OS."""

from __future__ import annotations

import importlib.util


REQUIRED_MODULES = {
    "langgraph": "langgraph",
    "langgraph.checkpoint.sqlite": "langgraph-checkpoint-sqlite",
    "yaml": "PyYAML",
    "sentence_transformers": "sentence-transformers",
}


def main() -> int:
    missing = [package for module, package in REQUIRED_MODULES.items() if importlib.util.find_spec(module) is None]
    if missing:
        print("runtime_dependencies_missing: " + ", ".join(missing))
        print("install: python3 -m venv .venv && .venv/bin/pip install -r product-crew-os-skill/runtime/requirements-langgraph.txt")
        return 2
    print("check-runtime-dependencies: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
