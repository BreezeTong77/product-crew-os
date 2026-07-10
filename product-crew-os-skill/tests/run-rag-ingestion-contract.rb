#!/usr/bin/env ruby

require "yaml"

skill_root = File.expand_path("..", __dir__)
policy_path = File.join(skill_root, "config", "embedding-rag-policy.yaml")
schema_path = File.join(skill_root, "runtime", "db", "embedding-rag-schema.sql")
reference_path = File.join(skill_root, "references", "embedding-rag-adapter.md")

errors = []
def assert(errors, condition, message)
  errors << message unless condition
end

policy = YAML.load_file(policy_path)
schema = File.read(schema_path)
reference = File.read(reference_path)

assert(errors, policy.dig("source_ingestion", "ocr", "primary_engine") == "PaddleOCR", "OCR primary engine must be PaddleOCR")
assert(errors, policy.dig("source_ingestion", "ocr", "fallback_engine") == "Tesseract", "OCR fallback engine must be Tesseract")
%w[ocr_text ocr_confidence page_index bbox_json source_ref].each do |field|
  assert(errors, Array(policy.dig("source_ingestion", "ocr", "required_outputs")).include?(field), "OCR required output missing #{field}")
end

assert(errors, policy.dig("chunking", "strategy") == "semantic_structured_overlap", "chunking strategy must be semantic_structured_overlap")
assert(errors, policy.dig("chunking", "overlap", "enabled") == true, "chunk overlap must be enabled")
assert(errors, policy.dig("chunking", "overlap", "ratio").to_f.positive?, "chunk overlap ratio must be positive")
%w[source_ref section_path content_hash extraction_method ocr_confidence consent_ref].each do |field|
  assert(errors, Array(policy.dig("chunking", "required_metadata")).include?(field), "chunk metadata missing #{field}")
end

bge = policy.dig("providers", "local_open_source_bge_small_zh") || {}
assert(errors, bge["model_name"] == "BAAI/bge-small-zh-v1.5", "local open-source embedding model must be BAAI/bge-small-zh-v1.5")
assert(errors, bge["embedding_dim"].to_i == 512, "BGE small zh embedding dim must be 512")
assert(errors, bge["default_batch_size"].to_i > 0, "embedding batch size must be configured")
assert(errors, bge["normalize_embeddings"] == true, "local embeddings must be normalized")

assert(errors, policy.dig("vector_store", "default") == "sqlite_vec", "default vector store must be sqlite_vec")
assert(errors, policy.dig("vector_store", "lexical_index", "engine") == "sqlite_fts5", "lexical index must use sqlite_fts5")
assert(errors, policy.dig("batch_indexing", "enabled") == true, "batch indexing must be enabled")
assert(errors, policy.dig("incremental_update", "enabled") == true, "incremental update must be enabled")
assert(errors, Array(policy.dig("incremental_update", "change_detection")).include?("content_hash_changed"), "incremental update must track content_hash_changed")
assert(errors, policy.dig("maintenance", "cleanup_schedule").to_s != "", "maintenance cleanup schedule must be configured")

%w[rag_recall_at_1 rag_recall_at_3 rag_precision_at_3 retrieval_latency_p95_ms ocr_low_confidence_rate stale_chunk_rate index_update_failure_rate].each do |metric|
  assert(errors, Array(policy.dig("monitoring", "required_metrics")).include?(metric), "monitoring metric missing #{metric}")
end

%w[
  source_type source_uri_hash extraction_method extraction_confidence artifact_version
  section_path chunk_strategy overlap_prev_chunk_id ocr_confidence ocr_bbox_json
  embedding_vector_indexes rag_ingestion_jobs rag_retrieval_quality_metrics rag_maintenance_events
  score_breakdown_json vector_store embedding_model stale
].each do |phrase|
  assert(errors, schema.include?(phrase), "embedding RAG schema missing #{phrase}")
end

%w[PaddleOCR Tesseract semantic_structured_overlap BAAI/bge-small-zh-v1.5 sqlite-vec FTS5 incremental update maintenance recall precision].each do |phrase|
  assert(errors, reference.include?(phrase), "embedding RAG reference missing #{phrase}")
end

if errors.empty?
  puts "run-rag-ingestion-contract: PASS"
else
  warn "run-rag-ingestion-contract: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
