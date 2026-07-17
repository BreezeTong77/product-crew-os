#!/usr/bin/env python3
"""Verify that a deployed host is actually connected to the LangGraph bridge."""

from __future__ import annotations

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main() -> int:
    base_url = os.environ.get("PCO_HOST_RUNTIME_URL", "").rstrip("/")
    token = os.environ.get("PCO_RUNTIME_TOKEN", "")
    if not base_url or not token:
        print("host_bridge_acceptance: deployment_required")
        print("set PCO_HOST_RUNTIME_URL and PCO_RUNTIME_TOKEN for the deployed Product Crew OS bridge")
        return 2

    request = Request(
        f"{base_url}/v1/handshake",
        data=b"{}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:  # nosec B310 - explicit user-configured deployment URL
            payload = json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"host_bridge_acceptance: FAIL ({error})")
        return 1

    errors = []
    if payload.get("runtime") != "python_langgraph":
        errors.append("runtime is not python_langgraph")
    if payload.get("stage_control") != "langgraph":
        errors.append("stage control is not langgraph")
    if payload.get("standard_sop_status") != "ready_for_standard_sop":
        missing = ", ".join(payload.get("missing_capabilities", []))
        errors.append(f"standard SOP is not ready: {missing or 'unknown capability gap'}")
    if errors:
        print("host_bridge_acceptance: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("host_bridge_acceptance: PASS")
    print("host is connected to the Python LangGraph control plane and ready for Standard SOP")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
