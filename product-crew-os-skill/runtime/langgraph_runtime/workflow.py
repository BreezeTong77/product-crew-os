"""Product Crew OS orchestration implemented as a persistent LangGraph.

The graph owns workflow control only. Skills, RAG providers, MCP tools, and
sub-agent delegates remain adapters that must return evidence before a gate can
pass. This keeps professional skill methods flexible without letting an adapter
change stages, decide gates, or write project memory on its own.
"""

from __future__ import annotations

import json
import hashlib
import hmac
import os
import re
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, TypedDict

import yaml
from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt

from .adapters import PersistentRagStore, SkillExecutionAdapter


class WorkflowState(TypedDict, total=False):
    project_id: str
    thread_id: str
    user_input: str
    requested_route_decision_id: str
    require_real_embedding: bool
    retrieval_evidence: Dict[str, Any]
    project_context: Dict[str, Any]
    route: Dict[str, Any]
    skill_execution: Dict[str, Any]
    artifact: Dict[str, Any]
    context_packets: List[Dict[str, Any]]
    review_callbacks: List[Dict[str, Any]]
    review_validation: Dict[str, Any]
    review_summary: Dict[str, Any]
    revision_count: int
    gate_status: str
    gate_result: str
    user_decision: Dict[str, Any]
    events: List[Dict[str, Any]]


class ProductCrewLangGraphRuntime:
    """Persistent product workflow graph with human and external-review pauses."""

    NON_PRODUCT_PATTERNS = (
        r"天气",
        r"翻译.*邮件",
        r"翻译这",
        r"写.*代码",
        r"今天.*几号",
    )
    PRODUCT_PATTERNS = (
        r"产品",
        r"需求",
        r"PRD",
        r"MVP",
        r"原型",
        r"审核",
        r"用户",
        r"功能",
        r"上线",
        r"指标",
        r"SOP",
    )
    STAGE_PATTERNS = (
        ("formal_requirements_review", (r"正式需求评审", r"正式评审")),
        ("low_fi_prototype", (r"原型", r"页面", r"低保真")),
        ("prd_v0_draft", (r"PRD", r"需求文档")),
        ("mvp_scope", (r"MVP", r"砍范围", r"第一版范围")),
        ("opportunity_tree", (r"机会树",)),
        ("research_plan", (r"调研计划", r"访谈")),
        ("request_triage", (r"先做什么", r"下一步", r"不知道", r"判断.*阶段")),
    )

    def __init__(self, workspace: str | Path, skill_root: str | Path, delegate_secret: Optional[str] = None):
        self.workspace = Path(workspace).expanduser().resolve()
        self.skill_root = Path(skill_root).expanduser().resolve()
        self.delegate_secret = delegate_secret or os.environ.get("PCO_LANGGRAPH_DELEGATE_SECRET", "")
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.project_db = self.workspace / "product-crew-langgraph.sqlite3"
        self.checkpoint_db = self.workspace / "product-crew-langgraph-checkpoints.sqlite3"
        self.rag_db = self.workspace / "product-crew-rag.sqlite3"
        self._create_project_schema()
        self._checkpoint_connection = sqlite3.connect(self.checkpoint_db, check_same_thread=False)
        self.checkpointer = SqliteSaver(self._checkpoint_connection)
        self.checkpointer.setup()
        self.graph = self._build_graph()

    def close(self) -> None:
        self._checkpoint_connection.close()

    def init_project(self, project_id: str, name: str) -> Dict[str, Any]:
        project_dir = self._project_dir(project_id)
        project_dir.mkdir(parents=True, exist_ok=True)
        now = self._now()
        with self._project_connection() as conn:
            conn.execute(
                """
                INSERT INTO langgraph_projects(project_id, name, workspace_path, current_stage_id, gate_status, created_at, updated_at)
                VALUES (?, ?, ?, '', 'not_started', ?, ?)
                ON CONFLICT(project_id) DO UPDATE SET name=excluded.name, updated_at=excluded.updated_at
                """,
                (project_id, name, str(project_dir), now, now),
            )
        self._write_project_state(project_id, {"project": name, "status": "active"})
        self._append_event(project_id, "project_initialized", {"name": name})
        return {"project_id": project_id, "workspace": str(project_dir), "checkpoint_db": str(self.checkpoint_db)}

    def run(
        self,
        project_id: str,
        user_input: str,
        *,
        skill_execution: Optional[Dict[str, Any]] = None,
        retrieval_evidence: Optional[Dict[str, Any]] = None,
        require_real_embedding: bool = False,
        thread_id: Optional[str] = None,
        route_decision_id: str = "",
    ) -> Dict[str, Any]:
        self._ensure_project(project_id)
        thread = thread_id or f"{project_id}:{uuid.uuid4().hex[:12]}"
        initial: WorkflowState = {
            "project_id": project_id,
            "thread_id": thread,
            "user_input": user_input,
            "requested_route_decision_id": route_decision_id,
            "skill_execution": skill_execution or {},
            "retrieval_evidence": retrieval_evidence or {},
            "require_real_embedding": require_real_embedding,
            "events": [],
        }
        return self.graph.invoke(initial, self._config(thread))

    def resume(self, thread_id: str, response: Dict[str, Any]) -> Dict[str, Any]:
        return self.graph.invoke(Command(resume=response), self._config(thread_id))

    def route_intent(self, project_id: str, user_input: str, retrieval_evidence: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Persist a route trace without creating an Artifact or Stage Gate."""
        self._ensure_project(project_id)
        state: WorkflowState = {
            "project_id": project_id,
            "thread_id": f"route:{uuid.uuid4().hex[:12]}",
            "user_input": user_input,
            "retrieval_evidence": retrieval_evidence or {},
            "skill_execution": {},
            "events": [],
        }
        state.update(self._input_scope_gate(state))
        if not state.get("route", {}).get("product_crew_os_applies", True):
            return state["route"]
        state.update(self._load_project_context(state))
        state.update(self._retrieve_evidence(state))
        state.update(self._route_stage(state))
        return state["route"]

    def execute_skill(self, skill_id: str, input_payload: Dict[str, Any]) -> Dict[str, Any]:
        return SkillExecutionAdapter(self.skill_root).execute(skill_id, input_payload)

    def rag_store(self) -> PersistentRagStore:
        return PersistentRagStore(self.rag_db)

    def draw_mermaid(self) -> str:
        return self.graph.get_graph().draw_mermaid()

    def sign_delegate_callback(self, session_id: str, callback: Dict[str, Any]) -> str:
        """Create the proof expected from a trusted external delegate adapter."""
        if not self.delegate_secret:
            raise ValueError("PCO_LANGGRAPH_DELEGATE_SECRET is required to sign a delegate callback")
        message = self._delegate_message(session_id, callback)
        return hmac.new(self.delegate_secret.encode("utf-8"), message.encode("utf-8"), hashlib.sha256).hexdigest()

    def _build_graph(self):
        builder = StateGraph(WorkflowState)
        builder.add_node("input_scope_gate", self._input_scope_gate)
        builder.add_node("load_project_context", self._load_project_context)
        builder.add_node("retrieve_evidence", self._retrieve_evidence)
        builder.add_node("route_stage", self._route_stage)
        builder.add_node("skill_execution_guard", self._skill_execution_guard)
        builder.add_node("write_artifact", self._write_artifact)
        builder.add_node("prepare_review", self._prepare_review)
        builder.add_node("await_external_review", self._await_external_review)
        builder.add_node("summarize_review", self._summarize_review)
        builder.add_node("await_user_decision", self._await_user_decision)
        builder.add_node("revise_artifact", self._revise_artifact)
        builder.add_node("write_project_memory", self._write_project_memory)
        builder.add_node("export_project_assets", self._export_project_assets)

        builder.add_edge(START, "input_scope_gate")
        builder.add_conditional_edges(
            "input_scope_gate",
            self._scope_branch,
            {"route": "load_project_context", "end": END},
        )
        builder.add_edge("load_project_context", "retrieve_evidence")
        builder.add_edge("retrieve_evidence", "route_stage")
        builder.add_conditional_edges(
            "route_stage",
            self._route_branch,
            {"execute": "skill_execution_guard", "end": END},
        )
        builder.add_edge("skill_execution_guard", "write_artifact")
        builder.add_conditional_edges(
            "write_artifact",
            self._artifact_branch,
            {"blocked": "write_project_memory", "review": "prepare_review", "gate": "await_user_decision"},
        )
        builder.add_conditional_edges(
            "prepare_review",
            self._review_branch,
            {"review": "await_external_review", "gate": "await_user_decision"},
        )
        builder.add_edge("await_external_review", "summarize_review")
        builder.add_edge("summarize_review", "await_user_decision")
        builder.add_conditional_edges(
            "await_user_decision",
            self._user_decision_branch,
            {"pass": "write_project_memory", "revise": "revise_artifact", "hold": "write_project_memory"},
        )
        builder.add_edge("revise_artifact", "prepare_review")
        builder.add_edge("write_project_memory", "export_project_assets")
        builder.add_edge("export_project_assets", END)
        return builder.compile(checkpointer=self.checkpointer, name="product_crew_os")

    def _input_scope_gate(self, state: WorkflowState) -> Dict[str, Any]:
        text = state["user_input"].strip()
        requested_route_decision_id = state.get("requested_route_decision_id", "")
        if requested_route_decision_id:
            return self._event_update(
                state,
                "input_scope_route_continuation_requested",
                {
                    "route_decision_id": requested_route_decision_id,
                    "persisted": self._persisted_route(state["project_id"], requested_route_decision_id) is not None,
                },
            )
        if any(re.search(pattern, text, re.IGNORECASE) for pattern in self.NON_PRODUCT_PATTERNS):
            route = {
                "product_crew_os_applies": False,
                "domain_intent": "non_product_task",
                "route_status": "domain_exit",
                "next_action": "Use the non-product capability without creating a project artifact.",
            }
            return self._update(state, route=route, gate_status="domain_exit")

        has_product_rule = any(re.search(pattern, text, re.IGNORECASE) for pattern in self.PRODUCT_PATTERNS)
        local_sop_score = self._best_local_prompt_eval_score(text)
        has_real_sop_candidate = self._has_real_sop_candidate(state.get("retrieval_evidence", {}))
        if not has_product_rule and local_sop_score < 0.25 and not has_real_sop_candidate:
            route = {
                "product_crew_os_applies": False,
                "domain_intent": "unclear",
                "route_status": "needs_clarification",
                "next_action": "Ask whether this is product work before entering Product Crew OS.",
                "local_sop_score": round(local_sop_score, 4),
            }
            return self._update(state, route=route, gate_status="needs_clarification")

        return self._event_update(
            state,
            "input_scope_passed",
            {"input": text, "local_sop_score": round(local_sop_score, 4), "real_sop_candidate": has_real_sop_candidate},
        )

    def _scope_branch(self, state: WorkflowState) -> Literal["route", "end"]:
        route = state.get("route", {})
        return "route" if route.get("product_crew_os_applies", True) else "end"

    def _load_project_context(self, state: WorkflowState) -> Dict[str, Any]:
        """Read durable project facts before route decisions, never chat history."""
        project_state_path = self._project_dir(state["project_id"]) / "project-state.json"
        persisted = {}
        if project_state_path.exists():
            try:
                persisted = json.loads(project_state_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                persisted = {"state_read_error": "project_state_invalid_json"}
        with self._project_connection() as conn:
            recent_events = conn.execute(
                "SELECT event_type, payload_json, created_at FROM langgraph_events WHERE project_id=? ORDER BY created_at DESC LIMIT 8",
                (state["project_id"],),
            ).fetchall()
        context = {
            "project_state": persisted,
            "recent_events": [
                {"event_type": row["event_type"], "payload": json.loads(row["payload_json"]), "created_at": row["created_at"]}
                for row in recent_events
            ],
        }
        return self._event_update(state, "project_context_loaded", {"event_count": len(context["recent_events"])}) | {"project_context": context}

    def _retrieve_evidence(self, state: WorkflowState) -> Dict[str, Any]:
        """Accept only structured retrieval evidence from a configured adapter."""
        evidence = dict(state.get("retrieval_evidence") or {})
        if not evidence:
            canonical = {
                "retrieval_mode": "rules_only",
                "embedding_status": "not_configured",
                "real_embedding_performed": False,
                "embedding_provider": "",
                "embedding_model": "",
                "source_refs": [],
            }
        elif evidence.get("real_embedding_performed") is True and all(
            evidence.get(key) for key in ("provider", "model", "source_refs")
        ):
            canonical = {
                "retrieval_mode": "real_embedding_sop_rag",
                "embedding_status": "real_embedding_performed",
                "real_embedding_performed": True,
                "embedding_provider": evidence["provider"],
                "embedding_model": evidence["model"],
                "source_refs": list(evidence["source_refs"]),
                "candidate_routes": list(evidence.get("candidate_routes", [])),
            }
        else:
            canonical = {
                "retrieval_mode": "adapter_evidence_invalid",
                "embedding_status": "invalid_embedding_evidence",
                "real_embedding_performed": False,
                "embedding_provider": evidence.get("provider", ""),
                "embedding_model": evidence.get("model", ""),
                "source_refs": list(evidence.get("source_refs", [])),
                "candidate_routes": list(evidence.get("candidate_routes", [])),
            }
        return self._event_update(state, "retrieval_evidence_checked", canonical) | {"retrieval_evidence": canonical}

    def _route_stage(self, state: WorkflowState) -> Dict[str, Any]:
        requested_route_decision_id = state.get("requested_route_decision_id", "")
        if requested_route_decision_id:
            persisted_route = self._persisted_route(state["project_id"], requested_route_decision_id)
            if not persisted_route:
                route = {
                    "product_crew_os_applies": True,
                    "route_decision_id": requested_route_decision_id,
                    "route_status": "route_decision_not_found",
                    "confidence": 0.0,
                }
                return self._update(state, route=route)
            return self._update(state, route=persisted_route)
        reference, route_match = self._select_stage_reference(state["user_input"], state.get("retrieval_evidence", {}))
        stage_id = route_match["stage_id"]
        embedding = self._embedding_evidence(state)
        route_status = "mapped"
        if state.get("require_real_embedding") and not embedding["real_embedding_performed"]:
            route_status = "needs_embedding_deployment"

        route = {
            "product_crew_os_applies": True,
            "domain_intent": "product_work",
            "route_decision_id": self._id("route"),
            "stage_id": stage_id,
            "macro_stage": reference.get("macro_stage", "opportunity_discovery"),
            "sop": stage_id,
            "primary_skill": reference.get("primary_skill", "pm-workbench"),
            "fallback_skill": reference.get("fallback_skill", ""),
            "required_roles": self._without_coach(reference.get("required_roles", [])),
            "triggered_roles": self._triggered_roles(reference.get("triggered_roles", []), state["user_input"]),
            "required_artifacts": reference.get("required_artifacts", ["triage-note.md"]),
            "stage_gate": reference.get("stage_gate", "user knows current stage and next artifact"),
            "candidate_routes": route_match["candidate_routes"],
            "confidence": route_match["confidence"],
            "route_status": route_status,
            "retrieval_mode": route_match["retrieval_mode"],
            "embedding_status": embedding["embedding_status"],
            "real_embedding_performed": embedding["real_embedding_performed"],
            "embedding_provider": embedding["embedding_provider"],
            "embedding_model": embedding["embedding_model"],
        }
        self._persist_route(state["project_id"], route)
        return self._update(state, route=route)

    def _route_branch(self, state: WorkflowState) -> Literal["execute", "end"]:
        status = state.get("route", {}).get("route_status")
        return "execute" if status == "mapped" else "end"

    def _skill_execution_guard(self, state: WorkflowState) -> Dict[str, Any]:
        route = state["route"]
        proof = dict(state.get("skill_execution") or {})
        expected_skill = route["primary_skill"]
        issues: List[str] = []

        if proof.get("skill_id") != expected_skill:
            issues.append("skill_id_mismatch_or_missing")
        if proof.get("execution_mode") not in {"native_capability", "external_workflow"}:
            issues.append("unsupported_execution_mode")
        if not proof.get("execution_id"):
            issues.append("execution_id_missing")
        if not proof.get("output_ref"):
            issues.append("output_ref_missing")
        if proof.get("contract_valid") is not True:
            issues.append("skill_contract_not_validated")
        if proof.get("may_change_stage") is not False:
            issues.append("skill_may_change_stage")
        if proof.get("may_decide_gate") is not False:
            issues.append("skill_may_decide_gate")
        if proof.get("may_write_project_memory") is not False:
            issues.append("skill_may_write_project_memory")
        if proof.get("may_call_agents") is not False:
            issues.append("skill_may_call_agents")

        valid = not issues
        status = "executed" if valid else "deployment_required"
        execution = {
            "skill_id": expected_skill,
            "execution_status": status,
            "gate_valid": valid,
            "issues": issues,
            "execution_id": proof.get("execution_id", ""),
            "output_ref": proof.get("output_ref", ""),
            "execution_mode": proof.get("execution_mode", "catalog_selected"),
            "contract_ref": proof.get("contract_ref", ""),
        }
        self._append_event(state["project_id"], "skill_execution_checked", execution)
        return self._update(state, skill_execution=execution)

    def _write_artifact(self, state: WorkflowState) -> Dict[str, Any]:
        route = state["route"]
        execution = state["skill_execution"]
        artifact_name = route["required_artifacts"][0] if route["required_artifacts"] else "product-crew-draft.md"
        artifact_id = self._id("art")
        status = "draft" if execution["gate_valid"] else "draft_not_gate_valid"
        content = self._draft_content(state)
        relative_path = Path("artifacts") / route["stage_id"] / f"{artifact_id}-{artifact_name}"
        output_path = self._project_dir(state["project_id"]) / relative_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(content, encoding="utf-8")
        artifact = {
            "artifact_id": artifact_id,
            "name": artifact_name,
            "path": str(output_path),
            "relative_path": str(relative_path),
            "status": status,
            "stage_id": route["stage_id"],
            "sop_id": route["sop"],
        }
        with self._project_connection() as conn:
            conn.execute(
                "INSERT INTO langgraph_artifacts(artifact_id, project_id, stage_id, name, path, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (artifact_id, state["project_id"], route["stage_id"], artifact_name, str(output_path), status, self._now()),
            )
        self._append_event(state["project_id"], "artifact_saved", artifact)
        return self._update(state, artifact=artifact)

    def _artifact_branch(self, state: WorkflowState) -> Literal["blocked", "review", "gate"]:
        if not state["skill_execution"]["gate_valid"]:
            return "blocked"
        roles = state["route"].get("required_roles", []) + state["route"].get("triggered_roles", [])
        return "review" if roles else "gate"

    def _prepare_review(self, state: WorkflowState) -> Dict[str, Any]:
        roles = self._unique(state["route"].get("required_roles", []) + state["route"].get("triggered_roles", []))
        packets = [self._build_context_packet(state, role_key) for role_key in roles]
        review = {
            "session_id": self._id("review"),
            "required_roles": roles,
            "status": "awaiting_external_review",
        }
        with self._project_connection() as conn:
            conn.execute(
                "INSERT INTO langgraph_review_sessions(session_id, project_id, artifact_id, required_roles_json, status, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                (review["session_id"], state["project_id"], state["artifact"]["artifact_id"], json.dumps(roles), review["status"], self._now()),
            )
        self._append_event(state["project_id"], "review_prepared", review)
        return self._update(state, context_packets=packets, review_validation=review)

    def _review_branch(self, state: WorkflowState) -> Literal["review", "gate"]:
        return "review" if state.get("context_packets") else "gate"

    def _await_external_review(self, state: WorkflowState) -> Dict[str, Any]:
        response = interrupt(
            {
                "kind": "external_review",
                "session_id": state["review_validation"]["session_id"],
                "artifact": state["artifact"],
                "context_packets": state["context_packets"],
                "message": "Provide real delegate callbacks. Simulated callbacks are invalid for the stage gate.",
            }
        )
        callbacks = list(response.get("callbacks", [])) if isinstance(response, dict) else []
        validation = self._validate_review_callbacks(state, callbacks)
        self._write_review_callbacks(state["project_id"], state["review_validation"]["session_id"], callbacks, validation)
        return self._update(state, review_callbacks=callbacks, review_validation=validation)

    def _summarize_review(self, state: WorkflowState) -> Dict[str, Any]:
        """Persist a neutral, inspectable review summary before asking the user."""
        callbacks = state.get("review_callbacks", [])
        must_fix = [item for item in callbacks if item.get("priority") == "must_fix"]
        summary = {
            "session_id": state.get("review_validation", {}).get("session_id", ""),
            "artifact_id": state["artifact"]["artifact_id"],
            "reviewed_roles": [item.get("role_key", "") for item in callbacks],
            "must_fix_count": len(must_fix),
            "status": state.get("review_validation", {}).get("status", ""),
            "user_decision_required": True,
        }
        path = self._project_dir(state["project_id"]) / "review-summaries" / f"{summary['session_id']}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# Review Summary",
            "",
            f"- Session: `{summary['session_id']}`",
            f"- Artifact: `{summary['artifact_id']}`",
            f"- Roles: `{', '.join(summary['reviewed_roles'])}`",
            f"- Must-fix count: `{summary['must_fix_count']}`",
            f"- Validation: `{summary['status']}`",
            "",
            "The coach summarizes evidence only. The user owns adoption, rejection, deferral, revision, and gate approval.",
        ]
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        summary["path"] = str(path)
        return self._event_update(state, "review_summarized", summary) | {"review_summary": summary}

    def _await_user_decision(self, state: WorkflowState) -> Dict[str, Any]:
        preflight_issues = list(state["skill_execution"].get("issues", []))
        if state.get("context_packets") and not state.get("review_validation", {}).get("gate_valid", False):
            preflight_issues.extend(state.get("review_validation", {}).get("issues", []))
        if preflight_issues:
            return self._update(
                state,
                gate_status="blocked_runtime_preflight",
                gate_result="; ".join(self._unique(preflight_issues)),
            )

        decision = interrupt(
            {
                "kind": "user_stage_decision",
                "stage_id": state["route"]["stage_id"],
                "artifact": state["artifact"],
                "message": "Only the user may approve, reject, defer, or request more evidence.",
            }
        )
        confirmed = isinstance(decision, dict) and decision.get("user_confirmed") is True
        approved = isinstance(decision, dict) and decision.get("action") in {"approve", "conditional_pass"}
        if confirmed and approved:
            return self._update(state, user_decision=decision, gate_status="pass", gate_result="user_confirmed")
        if isinstance(decision, dict) and decision.get("action") == "revise":
            revision_content = str(decision.get("revision_content", "")).strip()
            if not revision_content:
                return self._update(
                    state,
                    user_decision=decision,
                    gate_status="awaiting_user_decision",
                    gate_result="revision_content_required",
                )
            return self._update(
                state,
                user_decision=decision,
                gate_status="revision_requested",
                gate_result="user_requested_artifact_revision",
            )
        return self._update(
            state,
            user_decision=decision if isinstance(decision, dict) else {},
            gate_status="awaiting_user_decision",
            gate_result="user did not confirm a passing decision",
        )

    def _user_decision_branch(self, state: WorkflowState) -> Literal["pass", "revise", "hold"]:
        if state.get("gate_status") == "pass":
            return "pass"
        if state.get("gate_status") == "revision_requested":
            return "revise"
        return "hold"

    def _revise_artifact(self, state: WorkflowState) -> Dict[str, Any]:
        revision_number = int(state.get("revision_count", 0)) + 1
        decision = state.get("user_decision", {})
        revision_content = str(decision.get("revision_content", "")).strip()
        artifact = dict(state["artifact"])
        prior_path = Path(artifact["path"])
        versioned_path = prior_path.with_name(f"{prior_path.stem}-v{revision_number + 1}{prior_path.suffix}")
        body = prior_path.read_text(encoding="utf-8") if prior_path.exists() else ""
        versioned_path.write_text(
            f"{body.rstrip()}\n\n## User-requested revision {revision_number}\n\n{revision_content}\n",
            encoding="utf-8",
        )
        artifact.update({"path": str(versioned_path), "status": "revised_pending_review", "revision": revision_number + 1})
        with self._project_connection() as conn:
            conn.execute(
                "INSERT INTO langgraph_artifact_revisions(revision_id, artifact_id, project_id, revision, path, source, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (self._id("rev"), artifact["artifact_id"], state["project_id"], artifact["revision"], str(versioned_path), "user_requested_revision", self._now()),
            )
        self._append_event(state["project_id"], "artifact_revised", {"artifact_id": artifact["artifact_id"], "revision": artifact["revision"], "path": artifact["path"]})
        return self._update(
            state,
            artifact=artifact,
            revision_count=revision_number,
            context_packets=[],
            review_callbacks=[],
            review_validation={},
            review_summary={},
            gate_status="awaiting_external_review",
            gate_result="artifact_revised_rereview_required",
        )

    def _write_project_memory(self, state: WorkflowState) -> Dict[str, Any]:
        gate_status = state.get("gate_status") or "blocked_runtime_preflight"
        payload = {
            "project_id": state["project_id"],
            "current_stage_id": state.get("route", {}).get("stage_id", ""),
            "gate_status": gate_status,
            "artifact": state.get("artifact", {}),
            "route": state.get("route", {}),
            "skill_execution": state.get("skill_execution", {}),
            "review": state.get("review_validation", {}),
            "user_decision": state.get("user_decision", {}),
            "review_summary": state.get("review_summary", {}),
            "updated_at": self._now(),
        }
        self._write_project_state(state["project_id"], payload)
        self._append_event(state["project_id"], "stage_gate_recorded", {"gate_status": gate_status, "result": state.get("gate_result", "")})
        with self._project_connection() as conn:
            conn.execute(
                "UPDATE langgraph_projects SET current_stage_id=?, gate_status=?, updated_at=? WHERE project_id=?",
                (payload["current_stage_id"], gate_status, self._now(), state["project_id"]),
            )
        updates = self._event_update(state, "project_memory_written", {"gate_status": gate_status})
        updates["gate_status"] = gate_status
        updates["gate_result"] = state.get("gate_result", "")
        return updates

    def _export_project_assets(self, state: WorkflowState) -> Dict[str, Any]:
        project_root = self._project_dir(state["project_id"])
        artifact = state.get("artifact", {})
        home = project_root / "00_项目首页.md"
        home.write_text(
            "# 项目首页\n\n"
            f"- 当前 Stage：`{state.get('route', {}).get('stage_id', '')}`\n"
            f"- Gate：`{state.get('gate_status', '')}`\n"
            f"- 当前 Artifact：`{artifact.get('name', '')}`\n"
            f"- Artifact 路径：`{artifact.get('relative_path', artifact.get('path', ''))}`\n"
            f"- 下一步：`{state.get('gate_result', '')}`\n",
            encoding="utf-8",
        )
        manifest = {"project_id": state["project_id"], "home": str(home), "artifact": artifact, "exported_at": self._now()}
        (project_root / "export-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        return self._event_update(state, "project_assets_exported", manifest) | {"project_asset_pack": manifest}

    def _stage_reference(self, stage_id: str) -> Dict[str, Any]:
        for case in self._prompt_eval_cases():
            if case.get("stage_id") == stage_id:
                return self._case_reference(case)
        return {
            "macro_stage": "opportunity_discovery",
            "primary_skill": "pm-workbench",
            "fallback_skill": "",
            "required_roles": ["Coach"],
            "triggered_roles": [],
            "required_artifacts": ["triage-note.md"],
            "stage_gate": "user knows current stage and next artifact",
        }

    def _select_stage_reference(self, user_input: str, retrieval_evidence: Dict[str, Any]) -> tuple[Dict[str, Any], Dict[str, Any]]:
        """Resolve all 44 SOPs before falling back to a small alias list.

        The local prompt-eval index is intentionally evidence-labelled lexical
        retrieval, not a pretend embedding. A host-provided candidate can take
        precedence only when Retrieval Evidence Guard has marked it as a real
        embedding result with provider, model and source references.
        """
        cases = self._prompt_eval_cases()
        by_stage = {case["stage_id"]: case for case in cases}
        evidence_is_real = retrieval_evidence.get("real_embedding_performed") is True
        external_candidates = retrieval_evidence.get("candidate_routes", [])
        if evidence_is_real and isinstance(external_candidates, list):
            valid = [candidate for candidate in external_candidates if candidate.get("stage_id") in by_stage]
            valid.sort(key=lambda item: float(item.get("score", item.get("similarity", 0))), reverse=True)
            if valid:
                top = valid[0]
                confidence = float(top.get("score", top.get("similarity", 0)))
                routes = [
                    {
                        "stage_id": item["stage_id"],
                        "score": round(float(item.get("score", item.get("similarity", 0))), 4),
                        "source": "real_embedding_adapter",
                    }
                    for item in valid[:3]
                ]
                return self._case_reference(by_stage[top["stage_id"]]), {
                    "stage_id": top["stage_id"],
                    "confidence": confidence,
                    "candidate_routes": routes,
                    "retrieval_mode": "real_embedding_adapter",
                }

        normalized = self._normalize_text(user_input)
        scored = []
        for case in cases:
            score = self._lexical_similarity(normalized, self._normalize_text(case["user_input"]))
            scored.append((score, case))
        scored.sort(key=lambda item: item[0], reverse=True)
        candidates = [
            {"stage_id": case["stage_id"], "score": round(score, 4), "source": "local_prompt_eval"}
            for score, case in scored[:3]
        ]
        best_score, best_case = scored[0]
        second_score = scored[1][0] if len(scored) > 1 else 0.0
        if best_score >= 0.25 and (best_score - second_score >= 0.06 or best_score == 1.0):
            return self._case_reference(best_case), {
                "stage_id": best_case["stage_id"],
                "confidence": round(best_score, 4),
                "candidate_routes": candidates,
                "retrieval_mode": "local_prompt_eval_lexical",
            }

        for stage_id, patterns in self.STAGE_PATTERNS:
            if any(re.search(pattern, user_input, re.IGNORECASE) for pattern in patterns):
                return self._stage_reference(stage_id), {
                    "stage_id": stage_id,
                    "confidence": 0.78,
                    "candidate_routes": candidates,
                    "retrieval_mode": "stage_alias_rules",
                }

        return self._stage_reference("request_triage"), {
            "stage_id": "request_triage",
            "confidence": round(best_score, 4),
            "candidate_routes": candidates,
            "retrieval_mode": "local_prompt_eval_lexical",
        }

    def _prompt_eval_cases(self) -> List[Dict[str, Any]]:
        path = self.skill_root / "tests" / "prompt-eval-cases.yaml"
        return yaml.safe_load(path.read_text(encoding="utf-8")).get("cases", [])

    def _best_local_prompt_eval_score(self, user_input: str) -> float:
        normalized = self._normalize_text(user_input)
        return max(
            (self._lexical_similarity(normalized, self._normalize_text(case["user_input"])) for case in self._prompt_eval_cases()),
            default=0.0,
        )

    @staticmethod
    def _has_real_sop_candidate(evidence: Dict[str, Any]) -> bool:
        return (
            evidence.get("real_embedding_performed") is True
            and bool(evidence.get("provider"))
            and bool(evidence.get("model"))
            and bool(evidence.get("source_refs"))
            and isinstance(evidence.get("candidate_routes"), list)
            and bool(evidence["candidate_routes"])
        )

    @staticmethod
    def _case_reference(case: Dict[str, Any]) -> Dict[str, Any]:
        expected = case.get("expected", {})
        return {
            "macro_stage": case.get("macro_stage", "opportunity_discovery"),
            "primary_skill": expected.get("primary_skill", "pm-workbench"),
            "fallback_skill": expected.get("fallback_skill", ""),
            "required_roles": expected.get("required_roles", []),
            "triggered_roles": expected.get("triggered_roles", []),
            "required_artifacts": expected.get("required_artifacts", ["triage-note.md"]),
            "stage_gate": expected.get("stage_gate", "user knows current stage and next artifact"),
        }

    @staticmethod
    def _normalize_text(value: str) -> str:
        return re.sub(r"\s+", "", value.lower())

    @classmethod
    def _lexical_similarity(cls, left: str, right: str) -> float:
        def ngrams(value: str) -> set[str]:
            if len(value) < 2:
                return {value} if value else set()
            return {value[index : index + 2] for index in range(len(value) - 1)}

        left_terms = ngrams(left)
        right_terms = ngrams(right)
        if not left_terms or not right_terms:
            return 0.0
        return len(left_terms & right_terms) / len(left_terms | right_terms)

    def _embedding_evidence(self, state: WorkflowState) -> Dict[str, Any]:
        evidence = state.get("retrieval_evidence", {})
        return {
            "retrieval_mode": evidence.get("retrieval_mode", "rules_only"),
            "embedding_status": evidence.get("embedding_status", "not_configured"),
            "real_embedding_performed": evidence.get("real_embedding_performed") is True,
            "embedding_provider": evidence.get("embedding_provider", ""),
            "embedding_model": evidence.get("embedding_model", ""),
        }

    def _triggered_roles(self, configured_roles: List[str], user_input: str) -> List[str]:
        text = user_input.lower()
        trigger_terms = {
            "Research": ("用户", "调研", "验证", "不知道", "访谈"),
            "Biz": ("业务", "商业", "价值", "优先级", "收入", "资源"),
            "Tech": ("技术", "接口", "系统", "性能", "模型", "rag", "权限"),
            "Design": ("设计", "页面", "原型", "交互", "体验", "流程"),
            "Data": ("数据", "指标", "埋点", "归因", "实验"),
            "Customer": ("客户", "老板", "验收", "采购", "续约"),
            "CS": ("客服", "客户成功", "采纳", "培训", "支持"),
            "QA": ("测试", "验收", "回归", "缺陷", "边界"),
            "Legal": ("合规", "隐私", "敏感", "合同", "法务"),
            "Ops": ("运营", "灰度", "培训", "推广", "上线"),
        }
        roles: List[str] = []
        for role in configured_roles:
            if any(term in text for term in trigger_terms.get(role, ())):
                roles.append(role)
        return roles

    def _build_context_packet(self, state: WorkflowState, role_key: str) -> Dict[str, Any]:
        persona = self._persona(role_key)
        packet_id = self._id("ctx")
        packet = {
            "schema_version": "0.1",
            "packet_kind": "agent_context_packet",
            "packet_id": packet_id,
            "project_id": state["project_id"],
            "stage_id": state["route"]["stage_id"],
            "context_packet_quality": "complete",
            "persona_injection_status": "complete",
            "persona": persona,
            "artifact": state["artifact"],
            "review": {
                "role_key": role_key,
                "review_scope": "Review the current artifact only.",
                "evidence_boundary": "Use only the artifact and explicitly attached evidence.",
            },
            "invocation": {
                "real_invocation_required": True,
                "real_invocation_performed": False,
                "runtime_agent_id": "",
                "simulation_label_required_if_not_called": True,
            },
        }
        path = self._project_dir(state["project_id"]) / "context-packets" / f"{packet_id}.yaml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(packet, allow_unicode=True, sort_keys=False), encoding="utf-8")
        packet["path"] = str(path)
        return packet

    def _persona(self, role_key: str) -> Dict[str, Any]:
        config = yaml.safe_load((self.skill_root / "config" / "crew-personas.yaml").read_text(encoding="utf-8"))
        for persona in config.get("personas", {}).values():
            if persona.get("role_key") == role_key:
                required = ("role_key", "title", "display_name", "role", "personality", "speaking_style", "must_do", "must_not_do", "memory_focus")
                missing = [field for field in required if not persona.get(field)]
                if missing:
                    raise ValueError(f"persona incomplete for {role_key}: {', '.join(missing)}")
                return {
                    key: persona[key]
                    for key in required
                } | {"persona_source_ref": f"config/crew-personas.yaml#{role_key}"}
        raise ValueError(f"unknown role_key: {role_key}")

    def _validate_review_callbacks(self, state: WorkflowState, callbacks: List[Dict[str, Any]]) -> Dict[str, Any]:
        expected = {packet["persona"]["role_key"]: packet for packet in state.get("context_packets", [])}
        received = {callback.get("role_key"): callback for callback in callbacks}
        issues: List[str] = []
        for role_key, packet in expected.items():
            callback = received.get(role_key, {})
            if callback.get("real_invocation_performed") is not True:
                issues.append(f"{role_key}:real_invocation_missing")
            if not callback.get("runtime_agent_id"):
                issues.append(f"{role_key}:runtime_agent_id_missing")
            if callback.get("context_packet_id") != packet["packet_id"]:
                issues.append(f"{role_key}:context_packet_mismatch")
            if not callback.get("raw_review"):
                issues.append(f"{role_key}:raw_review_missing")
            if callback.get("simulation_label"):
                issues.append(f"{role_key}:simulated_result_invalid_for_gate")
            if not self.delegate_secret:
                issues.append(f"{role_key}:delegate_verifier_not_configured")
            elif not hmac.compare_digest(str(callback.get("delegate_proof", "")), self.sign_delegate_callback(state["review_validation"]["session_id"], callback)):
                issues.append(f"{role_key}:delegate_proof_invalid")
        return {
            "session_id": state["review_validation"]["session_id"],
            "status": "review_complete" if not issues else "review_invalid_for_gate",
            "gate_valid": not issues,
            "issues": issues,
        }

    def _write_review_callbacks(self, project_id: str, session_id: str, callbacks: List[Dict[str, Any]], validation: Dict[str, Any]) -> None:
        root = self._project_dir(project_id) / "raw-review-records" / session_id
        root.mkdir(parents=True, exist_ok=True)
        for callback in callbacks:
            role_key = callback.get("role_key", "unknown")
            (root / f"{role_key}.md").write_text(
                "# Raw Review Record\n\n"
                f"- Role: `{role_key}`\n"
                f"- Runtime agent: `{callback.get('runtime_agent_id', '')}`\n"
                # A host nickname is audit-only metadata. The configured role_key
                # and injected persona remain the identity used for gate checks.
                f"- Runtime nickname (audit only): `{callback.get('runtime_nickname', '')}`\n"
                f"- Context packet: `{callback.get('context_packet_id', '')}`\n"
                f"- Real invocation: `{callback.get('real_invocation_performed', False)}`\n\n"
                "## Raw Review\n\n"
                f"{callback.get('raw_review', '')}\n",
                encoding="utf-8",
            )
        with self._project_connection() as conn:
            conn.execute(
                "UPDATE langgraph_review_sessions SET status=?, validation_json=? WHERE session_id=?",
                (validation["status"], json.dumps(validation, ensure_ascii=False), session_id),
            )

    def _draft_content(self, state: WorkflowState) -> str:
        route = state["route"]
        execution = state["skill_execution"]
        if execution["gate_valid"]:
            return (
                f"# {route['required_artifacts'][0]}\n\n"
                f"- Stage: `{route['stage_id']}`\n"
                f"- Selected Skill: `{route['primary_skill']}`\n"
                f"- Execution evidence: `{execution['execution_id']}`\n\n"
                "This artifact was produced through a validated host or external skill execution."
            )
        return (
            f"# {route['required_artifacts'][0]}\n\n"
            "## Draft only\n\n"
            "The runtime saved this draft for traceability, but no validated Skill execution proof exists. "
            "It cannot be used to pass the stage gate.\n"
        )

    @staticmethod
    def _delegate_message(session_id: str, callback: Dict[str, Any]) -> str:
        payload = {
            "session_id": session_id,
            "role_key": callback.get("role_key", ""),
            "runtime_agent_id": callback.get("runtime_agent_id", ""),
            "runtime_nickname": callback.get("runtime_nickname", ""),
            "context_packet_id": callback.get("context_packet_id", ""),
            "raw_review": callback.get("raw_review", ""),
            "real_invocation_performed": callback.get("real_invocation_performed") is True,
        }
        return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    def _create_project_schema(self) -> None:
        with self._project_connection() as conn:
            conn.executescript(
                """
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS langgraph_projects (
                  project_id TEXT PRIMARY KEY,
                  name TEXT NOT NULL,
                  workspace_path TEXT NOT NULL,
                  current_stage_id TEXT NOT NULL DEFAULT '',
                  gate_status TEXT NOT NULL DEFAULT 'not_started',
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS langgraph_events (
                  event_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  event_type TEXT NOT NULL,
                  payload_json TEXT NOT NULL,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS langgraph_routes (
                  route_decision_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  payload_json TEXT NOT NULL,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS langgraph_artifacts (
                  artifact_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  stage_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  path TEXT NOT NULL,
                  status TEXT NOT NULL,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS langgraph_artifact_revisions (
                  revision_id TEXT PRIMARY KEY,
                  artifact_id TEXT NOT NULL,
                  project_id TEXT NOT NULL,
                  revision INTEGER NOT NULL,
                  path TEXT NOT NULL,
                  source TEXT NOT NULL,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS langgraph_review_sessions (
                  session_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  artifact_id TEXT NOT NULL,
                  required_roles_json TEXT NOT NULL,
                  status TEXT NOT NULL,
                  validation_json TEXT NOT NULL DEFAULT '{}',
                  created_at TEXT NOT NULL
                );
                """
            )

    def _project_connection(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.project_db)
        connection.row_factory = sqlite3.Row
        return connection

    def _ensure_project(self, project_id: str) -> None:
        with self._project_connection() as conn:
            row = conn.execute("SELECT project_id FROM langgraph_projects WHERE project_id=?", (project_id,)).fetchone()
        if not row:
            self.init_project(project_id, project_id)

    def _project_dir(self, project_id: str) -> Path:
        return self.workspace / "projects" / project_id

    def _write_project_state(self, project_id: str, payload: Dict[str, Any]) -> None:
        path = self._project_dir(project_id) / "project-state.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def _write_route_trace(self, project_id: str, route: Dict[str, Any]) -> None:
        path = self._project_dir(project_id) / "routing" / "stage-route-decision.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(route, ensure_ascii=False) + "\n")

    def _persist_route(self, project_id: str, route: Dict[str, Any]) -> None:
        with self._project_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO langgraph_routes(route_decision_id, project_id, payload_json, created_at) VALUES (?, ?, ?, ?)",
                (route["route_decision_id"], project_id, json.dumps(route, ensure_ascii=False), self._now()),
            )
        self._append_event(project_id, "stage_route_decision", route)
        self._write_route_trace(project_id, route)

    def _persisted_route(self, project_id: str, route_decision_id: str) -> Optional[Dict[str, Any]]:
        with self._project_connection() as conn:
            row = conn.execute(
                "SELECT payload_json FROM langgraph_routes WHERE project_id=? AND route_decision_id=?",
                (project_id, route_decision_id),
            ).fetchone()
        return json.loads(row["payload_json"]) if row else None

    def _append_event(self, project_id: str, event_type: str, payload: Dict[str, Any]) -> None:
        event = {"event_id": self._id("evt"), "event_type": event_type, "payload": payload, "created_at": self._now()}
        with self._project_connection() as conn:
            conn.execute(
                "INSERT INTO langgraph_events(event_id, project_id, event_type, payload_json, created_at) VALUES (?, ?, ?, ?, ?)",
                (event["event_id"], project_id, event_type, json.dumps(payload, ensure_ascii=False), event["created_at"]),
            )
        path = self._project_dir(project_id) / "event-log.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")

    def _event_update(self, state: WorkflowState, event_type: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        self._append_event(state["project_id"], event_type, payload)
        events = list(state.get("events", [])) + [{"event_type": event_type, "payload": payload}]
        return {"events": events}

    def _update(self, state: WorkflowState, **changes: Any) -> Dict[str, Any]:
        events = list(state.get("events", []))
        changes["events"] = events
        return changes

    @staticmethod
    def _without_coach(roles: List[str]) -> List[str]:
        return [role for role in roles if role != "Coach"]

    @staticmethod
    def _unique(values: List[str]) -> List[str]:
        return list(dict.fromkeys(value for value in values if value))

    @staticmethod
    def _id(prefix: str) -> str:
        return f"{prefix}_{uuid.uuid4().hex[:16]}"

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _config(thread_id: str) -> Dict[str, Dict[str, str]]:
        return {"configurable": {"thread_id": thread_id}}
