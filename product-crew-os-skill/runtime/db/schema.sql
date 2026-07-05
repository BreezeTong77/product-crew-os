PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;

CREATE TABLE IF NOT EXISTS projects (
  project_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  owner TEXT DEFAULT '',
  current_stage_id TEXT DEFAULT 'project_intake',
  current_macro_stage TEXT DEFAULT 'opportunity_discovery',
  status TEXT DEFAULT 'active',
  workspace_path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS stages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  stage_id TEXT NOT NULL,
  macro_stage TEXT DEFAULT '',
  status TEXT DEFAULT 'in_progress',
  gate_status TEXT DEFAULT 'not_ready',
  started_at TEXT NOT NULL,
  completed_at TEXT DEFAULT '',
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS sop_runs (
  run_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT NOT NULL,
  sop_id TEXT NOT NULL,
  user_input TEXT DEFAULT '',
  route_confidence TEXT DEFAULT '',
  result TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS skill_runs (
  run_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT DEFAULT '',
  skill_name TEXT NOT NULL,
  fallback_skill_name TEXT DEFAULT '',
  status TEXT DEFAULT 'planned',
  output_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS artifacts (
  artifact_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT NOT NULL,
  sop_id TEXT DEFAULT '',
  name TEXT NOT NULL,
  artifact_type TEXT DEFAULT 'markdown',
  current_version INTEGER DEFAULT 1,
  status TEXT DEFAULT 'draft',
  path TEXT NOT NULL,
  summary TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS artifact_versions (
  version_id TEXT PRIMARY KEY,
  artifact_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  status TEXT DEFAULT 'draft',
  path TEXT NOT NULL,
  content_hash TEXT DEFAULT '',
  source_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (artifact_id) REFERENCES artifacts(artifact_id),
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS decisions (
  decision_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT DEFAULT '',
  artifact_id TEXT DEFAULT '',
  title TEXT NOT NULL,
  decision TEXT NOT NULL,
  rationale TEXT DEFAULT '',
  impact TEXT DEFAULT '',
  verification TEXT DEFAULT '',
  source_ref TEXT DEFAULT '',
  status TEXT DEFAULT 'confirmed',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS review_items (
  review_item_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  artifact_id TEXT DEFAULT '',
  stage_id TEXT DEFAULT '',
  role_key TEXT DEFAULT '',
  reviewer_name TEXT DEFAULT '',
  comment TEXT NOT NULL,
  recommendation TEXT DEFAULT '',
  status TEXT DEFAULT 'open',
  source_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS review_sessions (
  session_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT DEFAULT '',
  artifact_id TEXT DEFAULT '',
  artifact_version INTEGER DEFAULT 1,
  status TEXT DEFAULT 'review_open',
  required_roles TEXT DEFAULT '',
  triggered_roles TEXT DEFAULT '',
  decision_owner TEXT DEFAULT 'user',
  path TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS raw_review_records (
  record_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  role_key TEXT NOT NULL,
  artifact_id TEXT DEFAULT '',
  context_packet_id TEXT DEFAULT '',
  invocation_id TEXT DEFAULT '',
  conclusion TEXT DEFAULT 'advice_only',
  raw_review TEXT NOT NULL,
  path TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS risks (
  risk_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT DEFAULT '',
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  severity TEXT DEFAULT 'medium',
  mitigation TEXT DEFAULT '',
  owner TEXT DEFAULT '',
  status TEXT DEFAULT 'open',
  source_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS next_actions (
  action_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  stage_id TEXT DEFAULT '',
  title TEXT NOT NULL,
  owner TEXT DEFAULT '',
  due_at TEXT DEFAULT '',
  dependency TEXT DEFAULT '',
  status TEXT DEFAULT 'open',
  source_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS sources (
  source_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  source_type TEXT DEFAULT '',
  title TEXT NOT NULL,
  path_or_url TEXT DEFAULT '',
  summary TEXT DEFAULT '',
  sensitivity TEXT DEFAULT 'normal',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS agent_personas (
  persona_id TEXT PRIMARY KEY,
  role_key TEXT NOT NULL,
  display_name TEXT NOT NULL,
  title TEXT DEFAULT '',
  base_style TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS agent_memories (
  memory_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  role_key TEXT NOT NULL,
  summary TEXT NOT NULL,
  source_ref TEXT DEFAULT '',
  confidence TEXT DEFAULT 'candidate',
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS context_packets (
  packet_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  role_key TEXT DEFAULT '',
  stage_id TEXT DEFAULT '',
  artifact_id TEXT DEFAULT '',
  path TEXT NOT NULL,
  token_budget INTEGER DEFAULT 2000,
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS agent_invocations (
  invocation_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  role_key TEXT NOT NULL,
  display_name TEXT DEFAULT '',
  runtime_agent_id TEXT DEFAULT '',
  context_packet_id TEXT DEFAULT '',
  real_invocation_performed INTEGER DEFAULT 0,
  simulation_label_used INTEGER DEFAULT 1,
  result TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS memory_deltas (
  delta_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  target_scope TEXT NOT NULL,
  target_path TEXT DEFAULT '',
  role_key TEXT DEFAULT '',
  source_ref TEXT DEFAULT '',
  confidence TEXT DEFAULT 'candidate',
  summary TEXT NOT NULL,
  status TEXT DEFAULT 'candidate',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT DEFAULT '{}',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE TABLE IF NOT EXISTS routing_feedback (
  feedback_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  user_input TEXT DEFAULT '',
  predicted_stage_id TEXT DEFAULT '',
  corrected_stage_id TEXT DEFAULT '',
  reason TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_documents USING fts5(
  project_id,
  doc_type,
  doc_id,
  title,
  body,
  source_ref
);
