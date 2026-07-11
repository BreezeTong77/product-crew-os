CREATE TABLE IF NOT EXISTS embedding_documents (
  doc_id TEXT PRIMARY KEY,
  namespace TEXT NOT NULL,
  scope TEXT NOT NULL,
  source_type TEXT DEFAULT '',
  source_uri_hash TEXT DEFAULT '',
  source_ref TEXT NOT NULL,
  owner TEXT DEFAULT '',
  title TEXT DEFAULT '',
  artifact_id TEXT DEFAULT '',
  artifact_version TEXT DEFAULT '',
  extraction_method TEXT DEFAULT '',
  extraction_confidence REAL DEFAULT 0,
  content_hash TEXT NOT NULL,
  index_hash TEXT DEFAULT '',
  pii_level TEXT DEFAULT 'none',
  consent_ref TEXT DEFAULT '',
  public_package_allowed INTEGER DEFAULT 0,
  source_mtime TEXT DEFAULT '',
  indexed_at TEXT DEFAULT '',
  deleted_at TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_embedding_documents_namespace
  ON embedding_documents(namespace);

CREATE INDEX IF NOT EXISTS idx_embedding_documents_source_ref
  ON embedding_documents(source_ref);

CREATE INDEX IF NOT EXISTS idx_embedding_documents_content_hash
  ON embedding_documents(content_hash);

CREATE TABLE IF NOT EXISTS embedding_chunks (
  chunk_id TEXT PRIMARY KEY,
  doc_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  source_ref TEXT DEFAULT '',
  section_path TEXT DEFAULT '',
  parent_heading TEXT DEFAULT '',
  chunk_strategy TEXT DEFAULT 'semantic_structured_overlap',
  overlap_prev_chunk_id TEXT DEFAULT '',
  overlap_next_chunk_id TEXT DEFAULT '',
  text TEXT NOT NULL,
  summary TEXT DEFAULT '',
  metadata_json TEXT DEFAULT '{}',
  source_type TEXT DEFAULT '',
  extraction_method TEXT DEFAULT '',
  ocr_engine TEXT DEFAULT '',
  ocr_confidence REAL DEFAULT 0,
  ocr_page_index INTEGER DEFAULT -1,
  ocr_bbox_json TEXT DEFAULT '{}',
  token_count INTEGER DEFAULT 0,
  char_count INTEGER DEFAULT 0,
  embedding_provider TEXT NOT NULL,
  embedding_model TEXT NOT NULL,
  embedding_dim INTEGER DEFAULT 0,
  vector_json TEXT DEFAULT '[]',
  content_hash TEXT NOT NULL,
  stale INTEGER DEFAULT 0,
  deleted_at TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(doc_id) REFERENCES embedding_documents(doc_id)
);

CREATE INDEX IF NOT EXISTS idx_embedding_chunks_doc_id
  ON embedding_chunks(doc_id);

CREATE INDEX IF NOT EXISTS idx_embedding_chunks_source_ref
  ON embedding_chunks(source_ref);

CREATE INDEX IF NOT EXISTS idx_embedding_chunks_content_hash
  ON embedding_chunks(content_hash);

CREATE INDEX IF NOT EXISTS idx_embedding_chunks_stale
  ON embedding_chunks(stale);

-- Optional local vector table when sqlite-vec is available.
-- Keep metadata in embedding_chunks so the index can be rebuilt.
CREATE TABLE IF NOT EXISTS embedding_vector_indexes (
  vector_index_id TEXT PRIMARY KEY,
  engine TEXT NOT NULL DEFAULT 'sqlite_vec',
  vector_table TEXT NOT NULL DEFAULT 'embedding_chunk_vectors',
  embedding_model TEXT NOT NULL,
  embedding_dim INTEGER NOT NULL,
  distance TEXT DEFAULT 'cosine',
  source_chunk_count INTEGER DEFAULT 0,
  last_rebuild_at TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rag_ingestion_jobs (
  job_id TEXT PRIMARY KEY,
  namespace TEXT NOT NULL,
  scope TEXT NOT NULL,
  source_ref TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_uri_hash TEXT DEFAULT '',
  artifact_id TEXT DEFAULT '',
  artifact_version TEXT DEFAULT '',
  extraction_method TEXT NOT NULL,
  ocr_engine TEXT DEFAULT '',
  status TEXT NOT NULL,
  batch_id TEXT DEFAULT '',
  idempotency_key TEXT NOT NULL,
  content_hash_before TEXT DEFAULT '',
  content_hash_after TEXT DEFAULT '',
  chunks_created INTEGER DEFAULT 0,
  chunks_updated INTEGER DEFAULT 0,
  chunks_deleted INTEGER DEFAULT 0,
  error_message TEXT DEFAULT '',
  started_at TEXT DEFAULT '',
  finished_at TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rag_ingestion_jobs_status
  ON rag_ingestion_jobs(status);

CREATE INDEX IF NOT EXISTS idx_rag_ingestion_jobs_source_ref
  ON rag_ingestion_jobs(source_ref);

CREATE TABLE IF NOT EXISTS embedding_retrieval_events (
  query_id TEXT PRIMARY KEY,
  turn_id TEXT DEFAULT '',
  namespace TEXT NOT NULL,
  query_text_hash TEXT NOT NULL,
  retrieval_mode TEXT NOT NULL,
  provider TEXT NOT NULL,
  vector_store TEXT DEFAULT '',
  embedding_model TEXT DEFAULT '',
  top_k INTEGER NOT NULL,
  top_candidates_json TEXT NOT NULL,
  score_breakdown_json TEXT DEFAULT '{}',
  selected_stage TEXT DEFAULT '',
  selected_sop TEXT DEFAULT '',
  selected_skill TEXT DEFAULT '',
  confidence REAL DEFAULT 0,
  confidence_gap REAL DEFAULT 0,
  used_for TEXT DEFAULT '',
  rejected_reason TEXT DEFAULT '',
  source_refs_json TEXT DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_embedding_retrieval_events_namespace
  ON embedding_retrieval_events(namespace);

CREATE INDEX IF NOT EXISTS idx_embedding_retrieval_events_used_for
  ON embedding_retrieval_events(used_for);

CREATE TABLE IF NOT EXISTS rag_retrieval_quality_metrics (
  metric_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  dataset_ref TEXT NOT NULL,
  namespace TEXT NOT NULL,
  retrieval_mode TEXT NOT NULL,
  provider TEXT NOT NULL,
  vector_store TEXT DEFAULT '',
  recall_at_1 REAL DEFAULT 0,
  recall_at_3 REAL DEFAULT 0,
  precision_at_3 REAL DEFAULT 0,
  mrr REAL DEFAULT 0,
  source_trace_rate REAL DEFAULT 0,
  namespace_isolation_violations INTEGER DEFAULT 0,
  retrieval_latency_p50_ms REAL DEFAULT 0,
  retrieval_latency_p95_ms REAL DEFAULT 0,
  embedding_batch_latency_ms REAL DEFAULT 0,
  ocr_low_confidence_rate REAL DEFAULT 0,
  stale_chunk_rate REAL DEFAULT 0,
  index_update_failure_rate REAL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rag_retrieval_quality_metrics_run_id
  ON rag_retrieval_quality_metrics(run_id);

CREATE TABLE IF NOT EXISTS rag_maintenance_events (
  maintenance_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  namespace TEXT NOT NULL,
  scope TEXT DEFAULT '',
  affected_sources INTEGER DEFAULT 0,
  affected_chunks INTEGER DEFAULT 0,
  stale_chunk_count INTEGER DEFAULT 0,
  orphan_chunk_count INTEGER DEFAULT 0,
  failure_count INTEGER DEFAULT 0,
  status TEXT NOT NULL,
  details_json TEXT DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rag_maintenance_events_type
  ON rag_maintenance_events(event_type);
