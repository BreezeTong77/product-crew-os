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
import secrets
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, TypedDict
from urllib import request as urlrequest

import yaml
from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt

from .adapters import PersistentRagStore, SkillExecutionAdapter
from .delegate_contract import sign_callback, verify_callback


class WorkflowState(TypedDict, total=False):
    project_id: str
    thread_id: str
    user_input: str
    requested_route_decision_id: str
    require_real_embedding: bool
    caller_supplied_retrieval_evidence: Dict[str, Any]
    retrieval_evidence: Dict[str, Any]
    project_context: Dict[str, Any]
    route: Dict[str, Any]
    skill_input: Dict[str, Any]
    caller_supplied_skill_execution: Dict[str, Any]
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

    def __init__(self, workspace: str | Path, skill_root: str | Path, delegate_secret: Optional[str] = None, rag_provider: Optional[Any] = None):
        self.workspace = Path(workspace).expanduser().resolve()
        self.skill_root = Path(skill_root).expanduser().resolve()
        self.delegate_secret = delegate_secret or os.environ.get("PCO_LANGGRAPH_DELEGATE_SECRET", "")
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.skill_receipt_secret = self._load_skill_receipt_secret()
        self.project_db = self.workspace / "product-crew-langgraph.sqlite3"
        self.checkpoint_db = self.workspace / "product-crew-langgraph-checkpoints.sqlite3"
        self.rag_db = self.workspace / "product-crew-rag.sqlite3"
        self._rag_store = PersistentRagStore(self.rag_db, provider=rag_provider)
        self._sop_rag_bootstrap: Optional[Dict[str, Any]] = None
        self._router_calibration = self._load_router_calibration()
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
        skill_input: Optional[Dict[str, Any]] = None,
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
            "skill_input": skill_input or {},
            # Kept only to report old-host attempts. It is never accepted as
            # evidence: the graph executes the selected Skill itself.
            "caller_supplied_skill_execution": skill_execution or {},
            "skill_execution": {},
            "caller_supplied_retrieval_evidence": retrieval_evidence or {},
            "retrieval_evidence": {},
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
            "caller_supplied_retrieval_evidence": retrieval_evidence or {},
            "retrieval_evidence": {},
            "skill_input": {},
            "skill_execution": {},
            "events": [],
        }
        state.update(self._retrieve_evidence(state))
        state.update(self._input_scope_gate(state))
        if not state.get("route", {}).get("product_crew_os_applies", True):
            return state["route"]
        state.update(self._load_project_context(state))
        state.update(self._route_stage(state))
        return state["route"]

    def execute_skill(self, skill_id: str, input_payload: Dict[str, Any]) -> Dict[str, Any]:
        """Run a Skill outside a Stage only as a visible preflight.

        This endpoint is useful for deployment checks but deliberately cannot
        mint a receipt that a Stage Gate accepts.
        """
        result = self._execute_skill_adapter(skill_id, input_payload)
        return result | {"invocation_scope": "standalone_preflight", "gate_valid": False}

    def _execute_skill_adapter(self, skill_id: str, input_payload: Dict[str, Any]) -> Dict[str, Any]:
        return SkillExecutionAdapter(self.skill_root).execute(skill_id, input_payload)

    def capability_handshake(self) -> Dict[str, Any]:
        """Report deployment facts; never infer real sub-agent calls from config."""
        skill_capabilities = SkillExecutionAdapter(self.skill_root).runtime_capabilities()
        provider = self.rag_store().provider
        embedding_available = bool(getattr(provider, "available", lambda: False)())
        index_stats = self.rag_store().stats()
        expected_sop_documents = len(self._prompt_eval_cases())
        graph_rag_ready = (
            self._sop_rag_bootstrap is not None
            and self._sop_rag_bootstrap.get("status") == "ready"
            and index_stats.get("documents", 0) >= expected_sop_documents
            and getattr(provider, "model", "") != "local_hash_dry_run"
        )
        binding_status = self._subagent_binding_status()
        signer_status = self._delegate_signer_status()
        missing = []
        if not embedding_available:
            missing.append("local_bge_embedding_runtime")
        if not graph_rag_ready:
            missing.append("product_rule_rag_index")
        if skill_capabilities["ollama"].get("status") != "ready":
            missing.append("ollama_skill_model")
        if binding_status["status"] != "bindings_declared":
            missing.append("coze_subagent_bindings")
        if signer_status["status"] != "ready":
            missing.append("coze_delegate_signer")
        return {
            "runtime": "python_langgraph",
            "stage_control": "langgraph",
            "standard_sop_status": "ready_for_standard_sop" if not missing else "runtime_degraded",
            "missing_capabilities": missing,
            "embedding": {
                "provider": getattr(provider, "model", ""),
                "package_status": "available" if embedding_available else "missing",
                "index_status": "ready" if graph_rag_ready else "bootstrap_required",
                "expected_sop_documents": expected_sop_documents,
                "index_stats": index_stats,
            },
            "skill_execution": skill_capabilities,
            "subagent_dispatch": binding_status,
            "delegate_signer": signer_status,
            "delegate_callback_proof": "hmac_sha256_required",
            "raw_review_visibility": "required",
            "note": "A declared sub-agent binding is only deployment readiness. Each Stage Gate still requires a real callback with runtime_agent_id and HMAC proof.",
        }

    @staticmethod
    def _delegate_signer_status() -> Dict[str, Any]:
        configured = os.environ.get("PCO_DELEGATE_SIGNER_URL", "").strip().rstrip("/")
        if not configured:
            return {"status": "not_configured", "url": ""}
        try:
            with urlrequest.urlopen(f"{configured}/health", timeout=3) as response:  # noqa: S310 - deployment URL is operator configured
                payload = json.loads(response.read().decode("utf-8"))
            if payload.get("status") == "ok" and payload.get("service") == "pco_delegate_signer":
                return {"status": "ready", "url": configured}
            return {"status": "unhealthy", "url": configured}
        except (OSError, ValueError, json.JSONDecodeError) as error:
            return {"status": "unreachable", "url": configured, "detail": str(error)}

    def bootstrap_product_rule_rag(self) -> Dict[str, Any]:
        """Build the graph-owned 44-SOP BGE index before standard SOP traffic."""
        bootstrap = self._bootstrap_sop_rag()
        provider = self.rag_store().provider
        stats = self.rag_store().stats()
        expected_sop_documents = len(self._prompt_eval_cases())
        real_embedding = getattr(provider, "model", "") != "local_hash_dry_run"
        ready = (
            bootstrap.get("status") == "ready"
            and real_embedding
            and stats.get("documents", 0) >= expected_sop_documents
        )
        return {
            "status": "ready" if ready else "runtime_blocked",
            "provider": getattr(provider, "model", ""),
            "real_embedding_performed": real_embedding and bootstrap.get("status") == "ready",
            "expected_sop_documents": expected_sop_documents,
            "index_stats": stats,
            "bootstrap": bootstrap,
        }

    def record_route_feedback(
        self,
        project_id: str,
        route_decision_id: str,
        outcome: str,
        corrected_stage_id: str = "",
        reason: str = "",
        source: str = "user",
    ) -> Dict[str, Any]:
        """Store one human-confirmed route outcome; never silently change routing."""
        if outcome not in {"confirmed", "corrected"}:
            raise ValueError("route feedback outcome must be confirmed or corrected")
        route = self._persisted_route(project_id, route_decision_id)
        if not route:
            raise ValueError("route_decision_id was not found for this project")
        predicted_stage_id = str(route.get("stage_id", ""))
        known_stages = {str(case.get("stage_id", "")) for case in self._prompt_eval_cases()}
        if outcome == "corrected":
            if not corrected_stage_id or corrected_stage_id not in known_stages:
                raise ValueError("corrected_stage_id must be one of the 44 SOP stage IDs")
            if corrected_stage_id == predicted_stage_id:
                raise ValueError("corrected_stage_id must differ from the predicted stage")
        elif corrected_stage_id:
            raise ValueError("confirmed feedback must not carry corrected_stage_id")

        feedback = {
            "feedback_id": self._id("routefb"),
            "project_id": project_id,
            "route_decision_id": route_decision_id,
            "predicted_stage_id": predicted_stage_id,
            "corrected_stage_id": corrected_stage_id,
            "outcome": outcome,
            "confidence": float(route.get("confidence", 0)),
            "retrieval_mode": str(route.get("retrieval_mode", "")),
            "reason": reason.strip(),
            "source": source,
            "created_at": self._now(),
        }
        with self._project_connection() as conn:
            if conn.execute(
                "SELECT feedback_id FROM langgraph_route_feedback WHERE project_id=? AND route_decision_id=?",
                (project_id, route_decision_id),
            ).fetchone():
                raise ValueError("route feedback was already recorded for this route_decision_id")
            conn.execute(
                "INSERT INTO langgraph_route_feedback(feedback_id, project_id, route_decision_id, predicted_stage_id, corrected_stage_id, outcome, confidence, retrieval_mode, reason, source, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    feedback["feedback_id"], project_id, route_decision_id, predicted_stage_id,
                    corrected_stage_id, outcome, feedback["confidence"], feedback["retrieval_mode"],
                    feedback["reason"], source, feedback["created_at"],
                ),
            )
        self._append_event(project_id, "route_feedback_recorded", feedback)
        if outcome == "corrected":
            feedback["bad_case"] = self._record_bad_case(
                project_id,
                category="sop_route_correction",
                summary=f"SOP route corrected from {predicted_stage_id} to {corrected_stage_id}",
                severity="medium",
                source=source,
                route_decision_id=route_decision_id,
                expected_value=corrected_stage_id,
                observed_value=predicted_stage_id,
                evidence={"confidence": feedback["confidence"], "retrieval_mode": feedback["retrieval_mode"], "reason": feedback["reason"]},
            )
        return feedback

    def operational_metrics(self, project_id: str) -> Dict[str, Any]:
        """Calculate evidence-based operations metrics and export them into the project vault."""
        self._ensure_project(project_id)
        with self._project_connection() as conn:
            route_rows = conn.execute(
                "SELECT route_decision_id FROM langgraph_routes WHERE project_id=?", (project_id,)
            ).fetchall()
            feedback_rows = conn.execute(
                "SELECT * FROM langgraph_route_feedback WHERE project_id=? ORDER BY created_at", (project_id,)
            ).fetchall()
            skill_rows = conn.execute(
                "SELECT stage_id, status, receipt_json FROM langgraph_skill_executions WHERE project_id=?", (project_id,)
            ).fetchall()
            review_rows = conn.execute(
                "SELECT session_id, required_roles_json, status FROM langgraph_review_sessions WHERE project_id=?", (project_id,)
            ).fetchall()
            invocation_rows = conn.execute(
                "SELECT session_id, role_key, gate_valid FROM langgraph_agent_invocations WHERE project_id=?", (project_id,)
            ).fetchall()
            bad_case_rows = conn.execute(
                "SELECT category, status FROM langgraph_bad_cases WHERE project_id=?", (project_id,)
            ).fetchall()

        feedback = [dict(row) for row in feedback_rows]
        confirmed = sum(1 for item in feedback if item["outcome"] == "confirmed")
        corrected = sum(1 for item in feedback if item["outcome"] == "corrected")
        evaluated = confirmed + corrected

        signed_executions = 0
        primary_executions = 0
        execution_statuses: Dict[str, int] = {}
        for row in skill_rows:
            receipt = json.loads(row["receipt_json"])
            status = str(row["status"])
            execution_statuses[status] = execution_statuses.get(status, 0) + 1
            if status == "executed" and self._valid_skill_receipt(project_id, str(row["stage_id"]), receipt):
                signed_executions += 1
                if receipt.get("skill_id") == receipt.get("primary_skill"):
                    primary_executions += 1

        expected_callback_slots = 0
        completed_sessions = 0
        for row in review_rows:
            try:
                expected_callback_slots += len(json.loads(row["required_roles_json"]))
            except json.JSONDecodeError:
                continue
            if row["status"] == "review_complete":
                completed_sessions += 1
        valid_callback_slots = {
            (str(row["session_id"]), str(row["role_key"]))
            for row in invocation_rows
            if int(row["gate_valid"]) == 1
        }
        observed_callback_slots = {(str(row["session_id"]), str(row["role_key"])) for row in invocation_rows}
        bad_case_by_category: Dict[str, int] = {}
        for row in bad_case_rows:
            category = str(row["category"])
            bad_case_by_category[category] = bad_case_by_category.get(category, 0) + 1

        metrics = {
            "schema_version": "0.1",
            "project_id": project_id,
            "measured_at": self._now(),
            "sop_routing": {
                "total_route_decisions": len(route_rows),
                "evaluated_by_human": evaluated,
                "confirmed_correct": confirmed,
                "corrected": corrected,
                "confirmed_accuracy": self._rate(confirmed, evaluated),
                "unverified": max(len(route_rows) - evaluated, 0),
                "definition": "Only human confirmed/corrected routes enter this accuracy rate; unreviewed routes are not silently counted as correct.",
            },
            "skill_execution": {
                "attempts": len(skill_rows),
                "signed_graph_executions": signed_executions,
                "true_execution_rate": self._rate(signed_executions, len(skill_rows)),
                "primary_skill_executions": primary_executions,
                "primary_skill_rate": self._rate(primary_executions, signed_executions),
                "status_breakdown": execution_statuses,
                "definition": "Success means an executed Skill with a Runtime-verified graph-issued receipt, not a template or caller claim.",
            },
            "subagent_feedback": {
                "review_sessions": len(review_rows),
                "completed_review_sessions": completed_sessions,
                "expected_callback_slots": expected_callback_slots,
                "observed_callback_slots": len(observed_callback_slots),
                "valid_callback_slots": len(valid_callback_slots),
                "real_callback_completion_rate": self._rate(len(valid_callback_slots), expected_callback_slots),
                "definition": "Completion requires a real, role-bound, signed callback that passes Runtime validation; simulated views do not count.",
            },
            "bad_cases": {
                "total": len(bad_case_rows),
                "open": sum(1 for row in bad_case_rows if row["status"] == "open"),
                "by_category": bad_case_by_category,
            },
            "calibration_review_queue": self._calibration_review_queue(feedback),
        }
        return self._write_operational_metrics(project_id, metrics)

    def list_bad_cases(self, project_id: str, status: str = "open") -> Dict[str, Any]:
        self._ensure_project(project_id)
        with self._project_connection() as conn:
            rows = conn.execute(
                "SELECT * FROM langgraph_bad_cases WHERE project_id=? AND (?='' OR status=?) ORDER BY created_at DESC",
                (project_id, status, status),
            ).fetchall()
        items = []
        for row in rows:
            item = dict(row)
            item["evidence"] = json.loads(item.pop("evidence_json"))
            items.append(item)
        return {"project_id": project_id, "status_filter": status, "items": items}

    def _subagent_binding_status(self) -> Dict[str, Any]:
        configured = os.environ.get("PCO_SUBAGENT_BINDINGS_PATH", "").strip()
        if not configured:
            return {"status": "bindings_not_configured", "path": ""}
        path = Path(configured).expanduser()
        if not path.is_file():
            return {"status": "bindings_file_missing", "path": str(path)}
        try:
            bindings = yaml.safe_load(path.read_text(encoding="utf-8")).get("bindings", {})
        except (OSError, yaml.YAMLError, AttributeError) as error:
            return {"status": "bindings_file_invalid", "path": str(path), "detail": str(error)}
        invalid = [
            role_key
            for role_key, value in bindings.items()
            if (
                not str((value or {}).get("coze_bot_id", "")).strip()
                or "REPLACE_WITH" in str((value or {}).get("coze_bot_id", ""))
                or not isinstance((value or {}).get("approved_runtime_agent_ids"), list)
                or not (value or {}).get("approved_runtime_agent_ids")
                or any(
                    not str(agent_id).strip() or "REPLACE_WITH" in str(agent_id)
                    for agent_id in (value or {}).get("approved_runtime_agent_ids", [])
                )
            )
        ]
        required_roles = {
            str(persona.get("role_key", ""))
            for persona in yaml.safe_load((self.skill_root / "config" / "crew-personas.yaml").read_text(encoding="utf-8")).get("personas", {}).values()
            if str(persona.get("role_key", "")) and str(persona.get("role_key", "")) != "Coach"
        }
        invalid.extend(sorted(required_roles - set(bindings)))
        if invalid:
            return {"status": "bindings_incomplete", "path": str(path), "invalid_roles": sorted(set(invalid))}
        return {"status": "bindings_declared", "path": str(path), "configured_roles": sorted(bindings)}

    def _approved_runtime_agent_ids(self, role_key: str) -> Optional[List[str]]:
        """Return a configured allow-list, or None when no binding file is active."""
        configured = os.environ.get("PCO_SUBAGENT_BINDINGS_PATH", "").strip()
        if not configured:
            return None
        path = Path(configured).expanduser()
        if not path.is_file():
            return []
        try:
            bindings = yaml.safe_load(path.read_text(encoding="utf-8")).get("bindings", {})
            value = bindings.get(role_key, {}) or {}
            return [str(agent_id).strip() for agent_id in value.get("approved_runtime_agent_ids", []) if str(agent_id).strip()]
        except (OSError, yaml.YAMLError, AttributeError):
            return []

    def _skill_candidates(self, route: Dict[str, Any]) -> List[str]:
        candidates = [str(route.get("primary_skill", "")).strip()]
        fallback = str(route.get("fallback_skill", ""))
        candidates.extend(item.strip() for item in fallback.split("/") if item.strip())
        return self._unique(candidates)

    def _skill_input(self, state: WorkflowState, skill_id: str) -> Dict[str, Any]:
        """Give Skills context without handing them workflow-control authority."""
        route = state["route"]
        supplied = dict(state.get("skill_input") or {})
        return {
            "skill_id": skill_id,
            "user_input": state["user_input"],
            "stage_id": route["stage_id"],
            "sop_id": route["sop"],
            "required_artifacts": route.get("required_artifacts", []),
            "project_context": state.get("project_context", {}),
            "retrieval_evidence": state.get("retrieval_evidence", {}),
            "user_supplied_input": supplied,
            # Command Skills use these when an integration has provided data.
            **supplied,
        }

    def rag_store(self) -> PersistentRagStore:
        return self._rag_store

    def draw_mermaid(self) -> str:
        return self.graph.get_graph().draw_mermaid()

    def sign_delegate_callback(self, session_id: str, callback: Dict[str, Any]) -> str:
        """Create the proof expected from a trusted external delegate adapter."""
        return sign_callback(self.delegate_secret, session_id, callback)

    def _build_graph(self):
        builder = StateGraph(WorkflowState)
        builder.add_node("input_scope_gate", self._input_scope_gate)
        builder.add_node("load_project_context", self._load_project_context)
        builder.add_node("retrieve_evidence", self._retrieve_evidence)
        builder.add_node("route_stage", self._route_stage)
        builder.add_node("execute_skill", self._execute_skill)
        builder.add_node("skill_execution_guard", self._skill_execution_guard)
        builder.add_node("write_artifact", self._write_artifact)
        builder.add_node("prepare_review", self._prepare_review)
        builder.add_node("await_external_review", self._await_external_review)
        builder.add_node("summarize_review", self._summarize_review)
        builder.add_node("await_user_decision", self._await_user_decision)
        builder.add_node("revise_artifact", self._revise_artifact)
        builder.add_node("write_project_memory", self._write_project_memory)
        builder.add_node("export_project_assets", self._export_project_assets)

        builder.add_edge(START, "retrieve_evidence")
        builder.add_edge("retrieve_evidence", "input_scope_gate")
        builder.add_conditional_edges(
            "input_scope_gate",
            self._scope_branch,
            {"route": "load_project_context", "end": END},
        )
        builder.add_edge("load_project_context", "route_stage")
        builder.add_conditional_edges(
            "route_stage",
            self._route_branch,
            {"execute": "execute_skill", "end": END},
        )
        builder.add_edge("execute_skill", "skill_execution_guard")
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
        """Build route evidence in graph; callers cannot self-certify embedding."""
        if any(re.search(pattern, state["user_input"], re.IGNORECASE) for pattern in self.NON_PRODUCT_PATTERNS):
            canonical = {
                "retrieval_mode": "skipped_hard_non_product",
                "embedding_status": "not_needed",
                "real_embedding_performed": False,
                "embedding_provider": "",
                "embedding_model": "",
                "source_refs": [],
                "candidate_routes": [],
            }
        else:
            caller_evidence = dict(state.get("caller_supplied_retrieval_evidence") or {})
            if caller_evidence:
                self._append_event(
                    state["project_id"],
                    "caller_retrieval_evidence_ignored",
                    {"reason": "only_graph_rag_may_certify_embedding", "claimed_provider": caller_evidence.get("provider", "")},
                )
            canonical = self._graph_rag_evidence(state["user_input"])
        return self._event_update(state, "retrieval_evidence_checked", canonical) | {"retrieval_evidence": canonical}

    def _graph_rag_evidence(self, query: str) -> Dict[str, Any]:
        bootstrap = self._bootstrap_sop_rag()
        if bootstrap.get("status") != "ready":
            return {
                "retrieval_mode": "graph_rag_runtime_blocked",
                "embedding_status": bootstrap.get("reason", "not_configured"),
                "real_embedding_performed": False,
                "embedding_provider": "",
                "embedding_model": "",
                "source_refs": [],
                "candidate_routes": [],
            }
        try:
            retrieved = self.rag_store().retrieve(query, namespace=PersistentRagStore.DEFAULT_NAMESPACE, top_k=3, used_for="stage_router")
        except RuntimeError as error:
            return {
                "retrieval_mode": "graph_rag_runtime_blocked",
                "embedding_status": str(error),
                "real_embedding_performed": False,
                "embedding_provider": "",
                "embedding_model": "",
                "source_refs": [],
                "candidate_routes": [],
            }
        real = retrieved.get("real_embedding_performed") is True
        candidates = [
            {"stage_id": item.get("stage_id"), "score": item.get("score", 0.0), "source_ref": item.get("source_ref", "")}
            for item in retrieved.get("candidates", [])
            if item.get("stage_id")
        ]
        return {
            "retrieval_mode": "graph_rag_real_embedding" if real else "graph_rag_smoke_only",
            "embedding_status": "real_embedding_performed" if real else "smoke_only_not_gate_valid",
            "real_embedding_performed": real,
            "embedding_provider": retrieved.get("provider", ""),
            "embedding_model": retrieved.get("model", ""),
            "source_refs": list(retrieved.get("source_refs", [])),
            "candidate_routes": candidates,
        }

    def _bootstrap_sop_rag(self) -> Dict[str, Any]:
        if self._sop_rag_bootstrap is not None:
            return self._sop_rag_bootstrap
        documents = []
        for case in self._prompt_eval_cases():
            expected = case.get("expected", {})
            documents.append(
                {
                    "source_ref": f"tests/prompt-eval-cases.yaml#{case.get('case_id', case['stage_id'])}",
                    "title": str(case["stage_id"]),
                    "content": "\n".join(
                        [
                            f"# {case['stage_id']}",
                            str(case.get("user_input", "")),
                            f"primary_skill: {expected.get('primary_skill', '')}",
                            f"fallback_skill: {expected.get('fallback_skill', '')}",
                        ]
                    ),
                    "metadata": {"stage_id": case["stage_id"], "case_id": case.get("case_id", "")},
                }
            )
        try:
            result = self.rag_store().upsert_documents(PersistentRagStore.DEFAULT_NAMESPACE, PersistentRagStore.DEFAULT_SCOPE, documents)
        except RuntimeError as error:
            self._sop_rag_bootstrap = {"status": "runtime_blocked", "reason": str(error)}
        else:
            self._sop_rag_bootstrap = {"status": "ready", "documents": len(documents), "index_result": result}
        return self._sop_rag_bootstrap

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
            "evidence_retrieval_mode": embedding["retrieval_mode"],
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

    def _execute_skill(self, state: WorkflowState) -> Dict[str, Any]:
        """Run the routed Skill inside the graph, then persist an engine receipt.

        The caller is never allowed to provide an execution receipt. This node
        is the sole place where a Stage can obtain one.
        """
        route = state["route"]
        if state.get("caller_supplied_skill_execution"):
            self._append_event(
                state["project_id"],
                "caller_skill_receipt_ignored",
                {
                    "stage_id": route["stage_id"],
                    "claimed_skill_id": state["caller_supplied_skill_execution"].get("skill_id", ""),
                    "reason": "only_graph_execute_skill_may_issue_receipts",
                },
            )
        attempts: List[Dict[str, Any]] = []
        result: Dict[str, Any] = {}
        for skill_id in self._skill_candidates(route):
            result = self._execute_skill_adapter(skill_id, self._skill_input(state, skill_id))
            attempts.append(
                {
                    "skill_id": skill_id,
                    "execution_status": result.get("execution_status", "unavailable"),
                    "driver": result.get("driver", result.get("reason", "")),
                }
            )
            if result.get("execution_status") == "executed":
                break

        execution_id = self._id("skillrun")
        selected_skill = str(result.get("skill_id") or route["primary_skill"])
        if result.get("execution_status") != "executed":
            execution = {
                "skill_id": selected_skill,
                "primary_skill": route["primary_skill"],
                "execution_status": result.get("execution_status", "deployment_required"),
                "gate_valid": False,
                "issues": ["skill_execution_not_completed"],
                "attempts": attempts,
                "deployment_notice": result.get("deployment_notice", {}),
                "detail": result.get("detail", result.get("reason", "")),
            }
            self._persist_skill_execution(state["project_id"], route["stage_id"], execution)
            self._record_bad_case(
                state["project_id"],
                category="skill_execution_blocked",
                summary=f"Skill {selected_skill} did not complete for {route['stage_id']}",
                severity="medium",
                source="runtime",
                expected_value="executed_with_graph_receipt",
                observed_value=str(execution["execution_status"]),
                evidence={"attempts": attempts, "detail": execution.get("detail", "")},
            )
            return self._event_update(state, "skill_execution_blocked", execution) | {"skill_execution": execution}

        output = str(result.get("output_content", "")).strip()
        if not output:
            execution = {
                "skill_id": selected_skill,
                "primary_skill": route["primary_skill"],
                "execution_status": "deployment_required",
                "gate_valid": False,
                "issues": ["skill_output_empty"],
                "attempts": attempts,
            }
            self._persist_skill_execution(state["project_id"], route["stage_id"], execution)
            self._record_bad_case(
                state["project_id"],
                category="skill_output_empty",
                summary=f"Skill {selected_skill} returned no usable output for {route['stage_id']}",
                severity="medium",
                source="runtime",
                expected_value="non_empty_artifact_output",
                observed_value="empty_output",
                evidence={"attempts": attempts},
            )
            return self._event_update(state, "skill_execution_blocked", execution) | {"skill_execution": execution}

        output_path = self._project_dir(state["project_id"]) / "skill-runs" / execution_id / "raw-output.md"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output + "\n", encoding="utf-8")
        receipt = {
            "execution_id": execution_id,
            "project_id": state["project_id"],
            "stage_id": route["stage_id"],
            "skill_id": selected_skill,
            "primary_skill": route["primary_skill"],
            "execution_mode": result.get("execution_mode", "external_workflow"),
            "output_ref": str(output_path),
            "output_sha256": hashlib.sha256(output.encode("utf-8")).hexdigest(),
            "source_ref": result.get("source_ref", ""),
            "driver": result.get("driver", ""),
            "executed_at": self._now(),
        }
        receipt_signature = self._sign_skill_receipt(receipt)
        execution = receipt | {
            "execution_status": "executed",
            "gate_valid": False,
            "contract_valid": True,
            "may_change_stage": False,
            "may_decide_gate": False,
            "may_write_project_memory": False,
            "may_call_agents": False,
            "receipt_signature": receipt_signature,
            "attempts": attempts,
            "execution_proof": result.get("execution_proof", {}),
        }
        self._persist_skill_execution(state["project_id"], route["stage_id"], execution)
        return self._event_update(state, "skill_executed_in_graph", execution) | {"skill_execution": execution}

    def _skill_execution_guard(self, state: WorkflowState) -> Dict[str, Any]:
        route = state["route"]
        proof = dict(state.get("skill_execution") or {})
        issues: List[str] = []

        if proof.get("skill_id") not in self._skill_candidates(route):
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
        if not self._valid_skill_receipt(state["project_id"], route["stage_id"], proof):
            issues.append("skill_receipt_invalid_or_not_graph_issued")

        valid = not issues
        status = "executed" if valid else "deployment_required"
        execution = {
            **proof,
            "execution_status": status,
            "gate_valid": valid,
            "issues": issues,
        }
        if not valid:
            self._record_bad_case(
                state["project_id"],
                category="skill_receipt_invalid",
                summary=f"Skill receipt failed validation for {route['stage_id']}",
                severity="high",
                source="runtime",
                expected_value="graph_issued_receipt",
                observed_value="receipt_invalid",
                evidence={"issues": issues, "skill_id": proof.get("skill_id", "")},
            )
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
        retrieval, not a pretend embedding. A graph-owned embedding candidate
        may take precedence only when its score and margin clear configured
        thresholds; otherwise rules remain the conservative fallback.
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
                second = float(valid[1].get("score", valid[1].get("similarity", 0))) if len(valid) > 1 else 0.0
                minimum_score = self._router_threshold("rag_route_min_score", "PCO_RAG_ROUTE_MIN_SCORE", 0.55)
                minimum_margin = self._router_threshold("rag_route_min_margin", "PCO_RAG_ROUTE_MIN_MARGIN", 0.04)
                routes = [
                    {
                        "stage_id": item["stage_id"],
                        "score": round(float(item.get("score", item.get("similarity", 0))), 4),
                        "source": "real_embedding_adapter",
                    }
                    for item in valid[:3]
                ]
                if confidence >= minimum_score and (confidence - second >= minimum_margin or confidence >= 0.82):
                    return self._case_reference(by_stage[top["stage_id"]]), {
                        "stage_id": top["stage_id"],
                        "confidence": confidence,
                        "candidate_routes": routes,
                        "retrieval_mode": "graph_rag_real_embedding",
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
        lexical_score = self._router_threshold("lexical_route_min_score", "PCO_LEXICAL_ROUTE_MIN_SCORE", 0.25)
        lexical_margin = self._router_threshold("lexical_route_min_margin", "PCO_LEXICAL_ROUTE_MIN_MARGIN", 0.06)
        if best_score >= lexical_score and (best_score - second_score >= lexical_margin or best_score == 1.0):
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

    def _has_real_sop_candidate(self, evidence: Dict[str, Any]) -> bool:
        candidates = evidence.get("candidate_routes", [])
        top_score = max((float(item.get("score", item.get("similarity", 0))) for item in candidates if isinstance(item, dict)), default=0.0)
        return (
            evidence.get("real_embedding_performed") is True
            and bool(evidence.get("embedding_provider") or evidence.get("provider"))
            and bool(evidence.get("embedding_model") or evidence.get("model"))
            and bool(evidence.get("source_refs"))
            and isinstance(candidates, list)
            and top_score >= self._router_threshold("domain_rag_min_score", "PCO_RAG_DOMAIN_MIN_SCORE", 0.50)
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
        if len(received) != len(callbacks):
            issues.append("duplicate_role_callback")
        for role_key in received:
            if role_key not in expected:
                issues.append(f"{role_key}:unexpected_review_role")
        for role_key, packet in expected.items():
            callback = received.get(role_key, {})
            if callback.get("real_invocation_performed") is not True:
                issues.append(f"{role_key}:real_invocation_missing")
            if not callback.get("runtime_agent_id"):
                issues.append(f"{role_key}:runtime_agent_id_missing")
            approved_agent_ids = self._approved_runtime_agent_ids(role_key)
            if approved_agent_ids is not None:
                if not approved_agent_ids:
                    issues.append(f"{role_key}:runtime_agent_binding_missing")
                elif str(callback.get("runtime_agent_id", "")) not in approved_agent_ids:
                    issues.append(f"{role_key}:runtime_agent_binding_mismatch")
                if not callback.get("coze_invocation_id"):
                    issues.append(f"{role_key}:coze_invocation_id_missing")
            if callback.get("context_packet_id") != packet["packet_id"]:
                issues.append(f"{role_key}:context_packet_mismatch")
            if callback.get("context_packet_quality") not in {None, "complete"}:
                issues.append(f"{role_key}:context_packet_quality_invalid")
            if callback.get("persona_injection_status") not in {None, "complete"}:
                issues.append(f"{role_key}:persona_injection_incomplete")
            if not callback.get("raw_review"):
                issues.append(f"{role_key}:raw_review_missing")
            if callback.get("simulation_label"):
                issues.append(f"{role_key}:simulated_result_invalid_for_gate")
            if callback.get("result") in {"advice_only", "invalid_for_gate", "simulated", "runtime_blocked"}:
                issues.append(f"{role_key}:callback_result_invalid_for_gate")
            if not self.delegate_secret:
                issues.append(f"{role_key}:delegate_verifier_not_configured")
            elif not verify_callback(self.delegate_secret, state["review_validation"]["session_id"], callback):
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
        global_issues = [issue for issue in validation.get("issues", []) if ":" not in issue]
        for callback in callbacks:
            role_key = callback.get("role_key", "unknown")
            raw_path = root / f"{role_key}.md"
            raw_path.write_text(
                "# Raw Review Record\n\n"
                f"- Role: `{role_key}`\n"
                f"- Runtime agent: `{callback.get('runtime_agent_id', '')}`\n"
                # A host nickname is audit-only metadata. The configured role_key
                # and injected persona remain the identity used for gate checks.
                f"- Runtime nickname (audit only): `{callback.get('runtime_nickname', '')}`\n"
                f"- Context packet: `{callback.get('context_packet_id', '')}`\n"
                f"- Coze invocation: `{callback.get('coze_invocation_id', '')}`\n"
                f"- Real invocation: `{callback.get('real_invocation_performed', False)}`\n\n"
                "## Raw Review\n\n"
                f"{callback.get('raw_review', '')}\n",
                encoding="utf-8",
            )
        with self._project_connection() as conn:
            for callback in callbacks:
                role_key = str(callback.get("role_key", "unknown"))
                role_issues = global_issues + [
                    issue for issue in validation.get("issues", []) if issue.startswith(f"{role_key}:")
                ]
                conn.execute(
                    "INSERT INTO langgraph_agent_invocations(invocation_id, session_id, project_id, role_key, runtime_agent_id, coze_invocation_id, context_packet_id, real_invocation_performed, gate_valid, result, raw_review_path, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        self._id("invoke"), session_id, project_id, role_key,
                        str(callback.get("runtime_agent_id", "")), str(callback.get("coze_invocation_id", "")),
                        str(callback.get("context_packet_id", "")),
                        1 if callback.get("real_invocation_performed") is True else 0,
                        0 if role_issues else 1,
                        str(callback.get("result", "")),
                        str(root / f"{role_key}.md"), self._now(),
                    ),
                )
            conn.execute(
                "UPDATE langgraph_review_sessions SET status=?, validation_json=? WHERE session_id=?",
                (validation["status"], json.dumps(validation, ensure_ascii=False), session_id),
            )
        if not validation.get("gate_valid", False):
            self._record_bad_case(
                project_id,
                category="subagent_callback_invalid",
                summary=f"Review callbacks failed validation for session {session_id}",
                severity="high",
                source="runtime",
                expected_value="real_role_bound_signed_callback",
                observed_value="invalid_callback",
                evidence={"session_id": session_id, "issues": validation.get("issues", [])},
            )

    def _draft_content(self, state: WorkflowState) -> str:
        route = state["route"]
        execution = state["skill_execution"]
        if execution["gate_valid"]:
            output_ref = Path(str(execution["output_ref"]))
            skill_output = output_ref.read_text(encoding="utf-8") if output_ref.is_file() else ""
            return (
                f"# {route['required_artifacts'][0]}\n\n"
                f"- Stage: `{route['stage_id']}`\n"
                f"- Selected Skill: `{execution['skill_id']}`\n"
                f"- Execution evidence: `{execution['execution_id']}`\n\n"
                "## Skill 原始输出\n\n"
                f"{skill_output}"
            )
        return (
            f"# {route['required_artifacts'][0]}\n\n"
            "## Draft only\n\n"
            "The runtime saved this draft for traceability, but no validated Skill execution proof exists. "
            "It cannot be used to pass the stage gate.\n"
        )

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
                CREATE TABLE IF NOT EXISTS langgraph_skill_executions (
                  execution_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  stage_id TEXT NOT NULL,
                  skill_id TEXT NOT NULL,
                  status TEXT NOT NULL,
                  receipt_json TEXT NOT NULL,
                  receipt_signature TEXT NOT NULL DEFAULT '',
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
                CREATE TABLE IF NOT EXISTS langgraph_route_feedback (
                  feedback_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  route_decision_id TEXT NOT NULL,
                  predicted_stage_id TEXT NOT NULL,
                  corrected_stage_id TEXT NOT NULL DEFAULT '',
                  outcome TEXT NOT NULL,
                  confidence REAL NOT NULL DEFAULT 0,
                  retrieval_mode TEXT NOT NULL DEFAULT '',
                  reason TEXT NOT NULL DEFAULT '',
                  source TEXT NOT NULL DEFAULT 'user',
                  created_at TEXT NOT NULL,
                  UNIQUE(project_id, route_decision_id)
                );
                CREATE TABLE IF NOT EXISTS langgraph_agent_invocations (
                  invocation_id TEXT PRIMARY KEY,
                  session_id TEXT NOT NULL,
                  project_id TEXT NOT NULL,
                  role_key TEXT NOT NULL,
                  runtime_agent_id TEXT NOT NULL DEFAULT '',
                  coze_invocation_id TEXT NOT NULL DEFAULT '',
                  context_packet_id TEXT NOT NULL DEFAULT '',
                  real_invocation_performed INTEGER NOT NULL DEFAULT 0,
                  gate_valid INTEGER NOT NULL DEFAULT 0,
                  result TEXT NOT NULL DEFAULT '',
                  raw_review_path TEXT NOT NULL DEFAULT '',
                  created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS langgraph_bad_cases (
                  bad_case_id TEXT PRIMARY KEY,
                  project_id TEXT NOT NULL,
                  category TEXT NOT NULL,
                  summary TEXT NOT NULL,
                  severity TEXT NOT NULL,
                  source TEXT NOT NULL,
                  route_decision_id TEXT NOT NULL DEFAULT '',
                  expected_value TEXT NOT NULL DEFAULT '',
                  observed_value TEXT NOT NULL DEFAULT '',
                  evidence_json TEXT NOT NULL DEFAULT '{}',
                  status TEXT NOT NULL DEFAULT 'open',
                  created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_langgraph_route_feedback_project ON langgraph_route_feedback(project_id, created_at);
                CREATE INDEX IF NOT EXISTS idx_langgraph_agent_invocations_project ON langgraph_agent_invocations(project_id, session_id, role_key);
                CREATE INDEX IF NOT EXISTS idx_langgraph_bad_cases_project ON langgraph_bad_cases(project_id, status, created_at);
                """
            )

    def _load_router_calibration(self) -> Dict[str, Any]:
        path = self.skill_root / "config" / "router-calibration.yaml"
        if not path.is_file():
            return {"thresholds": {}, "review_policy": {"same_route_correction_threshold": 3, "auto_apply": False}}
        try:
            payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError):
            return {"thresholds": {}, "review_policy": {"same_route_correction_threshold": 3, "auto_apply": False}}
        return payload if isinstance(payload, dict) else {"thresholds": {}, "review_policy": {"same_route_correction_threshold": 3, "auto_apply": False}}

    def _router_threshold(self, key: str, environment_key: str, default: float) -> float:
        configured = (self._router_calibration.get("thresholds", {}) or {}).get(key, default)
        raw = os.environ.get(environment_key, str(configured))
        try:
            return float(raw)
        except (TypeError, ValueError):
            return default

    def _record_bad_case(
        self,
        project_id: str,
        category: str,
        summary: str,
        severity: str,
        source: str,
        route_decision_id: str = "",
        expected_value: str = "",
        observed_value: str = "",
        evidence: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        bad_case = {
            "bad_case_id": self._id("badcase"),
            "project_id": project_id,
            "category": category,
            "summary": summary,
            "severity": severity,
            "source": source,
            "route_decision_id": route_decision_id,
            "expected_value": expected_value,
            "observed_value": observed_value,
            "evidence": evidence or {},
            "status": "open",
            "created_at": self._now(),
        }
        with self._project_connection() as conn:
            conn.execute(
                "INSERT INTO langgraph_bad_cases(bad_case_id, project_id, category, summary, severity, source, route_decision_id, expected_value, observed_value, evidence_json, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    bad_case["bad_case_id"], project_id, category, summary, severity, source,
                    route_decision_id, expected_value, observed_value,
                    json.dumps(bad_case["evidence"], ensure_ascii=False), "open", bad_case["created_at"],
                ),
            )
        self._append_event(project_id, "bad_case_recorded", bad_case)
        return bad_case

    @staticmethod
    def _rate(numerator: int, denominator: int) -> Optional[float]:
        return round(numerator / denominator, 4) if denominator else None

    def _calibration_review_queue(self, feedback: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        policy = self._router_calibration.get("review_policy", {}) or {}
        threshold = int(policy.get("same_route_correction_threshold", 3))
        grouped: Dict[tuple[str, str, str], List[Dict[str, Any]]] = {}
        for item in feedback:
            if item.get("outcome") != "corrected":
                continue
            key = (
                str(item.get("predicted_stage_id", "")),
                str(item.get("corrected_stage_id", "")),
                str(item.get("retrieval_mode", "")),
            )
            grouped.setdefault(key, []).append(item)

        queue: List[Dict[str, Any]] = []
        for (predicted, corrected, retrieval_mode), items in sorted(grouped.items()):
            if len(items) < threshold:
                continue
            average_confidence = round(sum(float(item.get("confidence", 0)) for item in items) / len(items), 4)
            control = "rag_route_min_margin" if retrieval_mode == "graph_rag_real_embedding" else "lexical_route_min_margin"
            suggestion = "补充该表达的 SOP 样本、别名和反例，再复跑基准集。"
            if average_confidence < 0.65:
                suggestion = f"先人工评估是否把 {control} 提高 0.02，让低把握命中优先进入澄清问题。"
            queue.append(
                {
                    "status": "pending_human_review",
                    "predicted_stage_id": predicted,
                    "corrected_stage_id": corrected,
                    "retrieval_mode": retrieval_mode,
                    "same_correction_count": len(items),
                    "average_confidence": average_confidence,
                    "candidate_control": control,
                    "suggestion": suggestion,
                    "auto_apply": False,
                }
            )
        return queue

    def _write_operational_metrics(self, project_id: str, metrics: Dict[str, Any]) -> Dict[str, Any]:
        root = self._project_dir(project_id) / "运营指标"
        root.mkdir(parents=True, exist_ok=True)
        json_path = root / "运营指标.json"
        markdown_path = root / "运营指标.md"
        json_path.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
        routing = metrics["sop_routing"]
        skill = metrics["skill_execution"]
        agent = metrics["subagent_feedback"]
        bad_cases = metrics["bad_cases"]
        recommendations = metrics["calibration_review_queue"]
        lines = [
            "# Product Crew OS 运营指标",
            "",
            "## SOP 命中",
            f"- 已确认样本：`{routing['evaluated_by_human']}`",
            f"- 用户确认正确：`{routing['confirmed_correct']}`",
            f"- 用户纠正：`{routing['corrected']}`",
            f"- 确认命中率：`{routing['confirmed_accuracy'] if routing['confirmed_accuracy'] is not None else '暂无样本'}`",
            "",
            "## Skill 真执行",
            f"- 执行尝试：`{skill['attempts']}`",
            f"- 有效图内回执：`{skill['signed_graph_executions']}`",
            f"- 真执行率：`{skill['true_execution_rate'] if skill['true_execution_rate'] is not None else '暂无样本'}`",
            "",
            "## 子 Agent 反馈",
            f"- 应回调角色数：`{agent['expected_callback_slots']}`",
            f"- 有效真实回调：`{agent['valid_callback_slots']}`",
            f"- 有效回调完成率：`{agent['real_callback_completion_rate'] if agent['real_callback_completion_rate'] is not None else '暂无样本'}`",
            "",
            "## Bad Case",
            f"- 总数：`{bad_cases['total']}`；待处理：`{bad_cases['open']}`",
            f"- 分类：`{json.dumps(bad_cases['by_category'], ensure_ascii=False)}`",
            "",
            "## 待人工确认的调参建议",
        ]
        if recommendations:
            for item in recommendations:
                lines.append(
                    f"- `{item['predicted_stage_id']}` 被纠正为 `{item['corrected_stage_id']}` 共 `{item['same_correction_count']}` 次：{item['suggestion']}"
                )
        else:
            lines.append("- 暂无达到阈值的同类纠正。系统不会自动改权重。")
        markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return metrics | {"artifact_paths": {"json": str(json_path), "markdown": str(markdown_path)}}

    def _load_skill_receipt_secret(self) -> str:
        """Use an installation-local secret so only this runtime issues receipts."""
        configured = os.environ.get("PCO_SKILL_RECEIPT_SECRET", "").strip()
        if configured:
            return configured
        secret_path = self.workspace / ".pco-skill-receipt-secret"
        if secret_path.is_file():
            return secret_path.read_text(encoding="utf-8").strip()
        secret = secrets.token_urlsafe(48)
        secret_path.write_text(secret, encoding="utf-8")
        try:
            secret_path.chmod(0o600)
        except OSError:
            pass
        return secret

    def _sign_skill_receipt(self, receipt: Dict[str, Any]) -> str:
        message = json.dumps(receipt, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return hmac.new(self.skill_receipt_secret.encode("utf-8"), message.encode("utf-8"), hashlib.sha256).hexdigest()

    def _persist_skill_execution(self, project_id: str, stage_id: str, execution: Dict[str, Any]) -> None:
        execution_id = str(execution.get("execution_id") or self._id("skillrun"))
        stored = dict(execution) | {"execution_id": execution_id}
        with self._project_connection() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO langgraph_skill_executions(execution_id, project_id, stage_id, skill_id, status, receipt_json, receipt_signature, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    execution_id,
                    project_id,
                    stage_id,
                    str(stored.get("skill_id", "")),
                    str(stored.get("execution_status", "deployment_required")),
                    json.dumps(stored, ensure_ascii=False),
                    str(stored.get("receipt_signature", "")),
                    self._now(),
                ),
            )

    def _valid_skill_receipt(self, project_id: str, stage_id: str, proof: Dict[str, Any]) -> bool:
        execution_id = str(proof.get("execution_id", ""))
        signature = str(proof.get("receipt_signature", ""))
        if not execution_id or not signature:
            return False
        with self._project_connection() as conn:
            row = conn.execute(
                "SELECT receipt_json, receipt_signature FROM langgraph_skill_executions WHERE execution_id=? AND project_id=? AND stage_id=? AND status='executed'",
                (execution_id, project_id, stage_id),
            ).fetchone()
        if not row:
            return False
        try:
            stored = json.loads(row["receipt_json"])
        except json.JSONDecodeError:
            return False
        signed_receipt = {
            key: stored.get(key, "")
            for key in (
                "execution_id",
                "project_id",
                "stage_id",
                "skill_id",
                "primary_skill",
                "execution_mode",
                "output_ref",
                "output_sha256",
                "source_ref",
                "driver",
                "executed_at",
            )
        }
        expected = self._sign_skill_receipt(signed_receipt)
        return (
            hmac.compare_digest(signature, str(row["receipt_signature"]))
            and hmac.compare_digest(signature, expected)
            and proof.get("skill_id") == stored.get("skill_id")
            and proof.get("output_ref") == stored.get("output_ref")
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
