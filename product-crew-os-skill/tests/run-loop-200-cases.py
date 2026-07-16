#!/usr/bin/env python3
"""Run the Python 51-case release gate four times without Ruby tooling."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=4)
    args = parser.parse_args()
    runner = Path(__file__).with_name("run-release-gate.py")
    for index in range(args.iterations):
        result = subprocess.run([sys.executable, str(runner)])
        if result.returncode:
            return result.returncode
        print(f"iteration {index + 1}/{args.iterations}: PASS")
    print(f"run-loop-200-cases: PASS ({args.iterations * 51} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
