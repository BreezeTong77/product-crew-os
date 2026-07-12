CREATE TABLE IF NOT EXISTS test_cases (
  case_id TEXT PRIMARY KEY,
  suite TEXT NOT NULL,
  case_type TEXT DEFAULT '',
  title TEXT DEFAULT '',
  source_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_status TEXT DEFAULT '',
  last_case_hash TEXT DEFAULT '',
  last_evidence TEXT DEFAULT '',
  last_run_at TEXT DEFAULT '',
  last_checked_at TEXT DEFAULT '',
  pass_count INTEGER DEFAULT 0,
  fail_count INTEGER DEFAULT 0,
  skip_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS suite_runs (
  suite_run_id TEXT PRIMARY KEY,
  suite TEXT NOT NULL,
  runner_version TEXT DEFAULT '',
  git_sha TEXT DEFAULT '',
  command TEXT DEFAULT '',
  force_rerun INTEGER DEFAULT 0,
  release_gate INTEGER DEFAULT 0,
  python_version TEXT DEFAULT '',
  sqlite_version TEXT DEFAULT '',
  status TEXT DEFAULT '',
  total_count INTEGER DEFAULT 0,
  pass_count INTEGER DEFAULT 0,
  fail_count INTEGER DEFAULT 0,
  skip_count INTEGER DEFAULT 0,
  actual_executed_count INTEGER DEFAULT 0,
  report_path TEXT DEFAULT '',
  started_at TEXT NOT NULL,
  finished_at TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS test_case_runs (
  run_id TEXT PRIMARY KEY,
  suite_run_id TEXT DEFAULT NULL,
  case_id TEXT NOT NULL,
  suite TEXT NOT NULL,
  case_type TEXT DEFAULT '',
  case_hash TEXT DEFAULT '',
  status TEXT DEFAULT '',
  evidence TEXT DEFAULT '',
  badcase TEXT DEFAULT '',
  source_ref TEXT DEFAULT '',
  expected_primary_skill TEXT DEFAULT '',
  selected_skill TEXT DEFAULT '',
  skill_status TEXT DEFAULT '',
  degrade_reason TEXT DEFAULT '',
  started_at TEXT NOT NULL,
  finished_at TEXT NOT NULL,
  FOREIGN KEY(case_id) REFERENCES test_cases(case_id),
  FOREIGN KEY(suite_run_id) REFERENCES suite_runs(suite_run_id)
);

CREATE INDEX IF NOT EXISTS idx_test_case_runs_case_id
  ON test_case_runs(case_id);

CREATE INDEX IF NOT EXISTS idx_test_case_runs_status
  ON test_case_runs(status);

CREATE TABLE IF NOT EXISTS badcases (
  badcase_id TEXT PRIMARY KEY,
  case_id TEXT DEFAULT '',
  title TEXT NOT NULL,
  symptom TEXT DEFAULT '',
  fix_summary TEXT DEFAULT '',
  regression_file TEXT DEFAULT '',
  status TEXT DEFAULT '',
  severity TEXT DEFAULT '',
  source_ref TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_badcases_case_id
  ON badcases(case_id);

CREATE INDEX IF NOT EXISTS idx_badcases_status
  ON badcases(status);
