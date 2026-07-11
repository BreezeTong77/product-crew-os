#!/usr/bin/env ruby

require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
RUNTIME = File.join(ROOT, "runtime")
$LOAD_PATH.unshift(RUNTIME)
require "embedding_provider"
require "sop_embedding_index"

def assert(errors, condition, message)
  errors << message unless condition
end

def query_count(db, sql)
  stdout, stderr, status = Open3.capture3("sqlite3", "-json", db, sql)
  raise "sqlite count failed: #{stderr}" unless status.success?

  JSON.parse(stdout).first.fetch("count").to_i
end

errors = []
Dir.mktmpdir("pco-persistent-sop-") do |dir|
  db = File.join(dir, "pco.sqlite3")
  prompt_eval = File.join(ROOT, "tests", "prompt-eval-cases.yaml")
  provider = ProductCrewOS::EmbeddingProviders::LocalHashDryRun.new
  index = ProductCrewOS::SopEmbeddingIndex.new(prompt_eval_path: prompt_eval, provider: provider, db_path: db)

  first = index.retrieve("先做 MVP，砍范围", top_k: 3)
  second = index.retrieve("先做 MVP，砍范围", top_k: 3)

  assert(errors, first["real_embedding_performed"] == false, "hash provider must never claim real embedding")
  assert(errors, first["vector_store"] == "sqlite_json_cosine_fallback", "persistent store must report its actual fallback engine")
  assert(errors, first.fetch("candidates").any? { |candidate| candidate["stage_id"] == "mvp_scope" }, "persistent SOP index did not retrieve MVP scope")
  assert(errors, second.fetch("candidates").all? { |candidate| Array(candidate["source_refs"]).any? }, "persistent SOP retrieval lost source refs")
  assert(errors, query_count(db, "SELECT COUNT(*) AS count FROM embedding_documents WHERE namespace = 'pco_rules';") == 44, "persistent SOP index should store 44 documents")
  assert(errors, query_count(db, "SELECT COUNT(*) AS count FROM embedding_chunks;") == 44, "persistent SOP index should store 44 chunks")
  assert(errors, query_count(db, "SELECT COUNT(*) AS count FROM rag_ingestion_jobs;") == 44, "unchanged SOP sources should not create duplicate ingestion jobs")
  assert(errors, query_count(db, "SELECT COUNT(*) AS count FROM embedding_retrieval_events;") == 2, "persistent SOP retrieval events were not written")

  store = ProductCrewOS::PersistentRagStore.new(db_path: db, provider: provider)
  begin
    store.upsert_documents(
      namespace: "project_demo",
      scope: "project_memory",
      documents: [{ source_ref: "project:demo", title: "Private", content: "Private project material" }]
    )
    errors << "private RAG namespace accepted a missing consent_ref"
  rescue RuntimeError => error
    assert(errors, error.message.include?("consent_ref"), "private namespace rejection did not explain consent")
  end
  store.upsert_documents(
    namespace: "project_demo",
    scope: "project_memory",
    consent_ref: "consent:test-project-demo",
    documents: [{ source_ref: "project:demo", title: "Private", content: "Private project material" }]
  )
  begin
    store.retrieve(query: "Private project", namespace: "project_demo", allowed_scopes: ["project_memory"])
    errors << "private RAG retrieval accepted a missing consent_ref"
  rescue RuntimeError => error
    assert(errors, error.message.include?("consent_ref"), "private retrieval rejection did not explain consent")
  end
  private_result = store.retrieve(
    query: "Private project",
    namespace: "project_demo",
    allowed_scopes: ["project_memory"],
    consent_ref: "consent:test-project-demo"
  )
  assert(errors, private_result.fetch("candidates").length == 1, "private RAG retrieval did not return consent-matched content")
end

if errors.empty?
  puts "run-persistent-sop-vector-index: PASS"
else
  warn "run-persistent-sop-vector-index: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
