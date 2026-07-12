"""Canonical proof helpers for callbacks from real external review delegates."""

from __future__ import annotations

import hashlib
import hmac
import json
from typing import Any, Dict


def callback_message(session_id: str, callback: Dict[str, Any]) -> str:
    """Serialize every callback field that can influence review or gate state."""
    payload = {key: value for key, value in callback.items() if key != "delegate_proof"}
    payload["session_id"] = session_id
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def sign_callback(delegate_secret: str, session_id: str, callback: Dict[str, Any]) -> str:
    if not delegate_secret:
        raise ValueError("PCO_LANGGRAPH_DELEGATE_SECRET is required to sign a delegate callback")
    return hmac.new(
        delegate_secret.encode("utf-8"),
        callback_message(session_id, callback).encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def verify_callback(delegate_secret: str, session_id: str, callback: Dict[str, Any]) -> bool:
    if not delegate_secret:
        return False
    supplied = str(callback.get("delegate_proof", ""))
    return hmac.compare_digest(supplied, sign_callback(delegate_secret, session_id, callback))
