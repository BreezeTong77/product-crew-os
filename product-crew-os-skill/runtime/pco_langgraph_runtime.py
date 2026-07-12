#!/usr/bin/env python3
"""Deprecated compatibility entrypoint for the Python-only runtime CLI."""

from pco_runtime import main


if __name__ == "__main__":
    raise SystemExit(main())
