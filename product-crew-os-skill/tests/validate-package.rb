#!/usr/bin/env ruby

require "json"
require "yaml"

skill_root = File.expand_path("..", __dir__)
errors = []

Dir[File.join(skill_root, "**", "*.{yaml,yml}")].sort.each do |path|
  YAML.load_file(path)
rescue StandardError => e
  errors << "YAML parse failed: #{path}: #{e.message}"
end

Dir[File.join(skill_root, "**", "*.json")].sort.each do |path|
  JSON.parse(File.read(path))
rescue StandardError => e
  errors << "JSON parse failed: #{path}: #{e.message}"
end

policy_path = File.join(skill_root, "config", "evolution-policy.yaml")
policy = YAML.load_file(policy_path)
required = policy.dig("regression_suite", "required_scenarios") || []

scenario_dir = File.join(skill_root, "tests", "scenarios")
actual = Dir[File.join(scenario_dir, "*.yaml")].sort.map do |path|
  YAML.load_file(path)["scenario_id"]
end.compact

missing = required - actual
extra = actual - required
errors << "Missing required scenarios: #{missing.join(", ")}" unless missing.empty?
errors << "Unregistered scenarios: #{extra.join(", ")}" unless extra.empty?

required_files = [
  "SKILL.md",
  "THIRD_PARTY_NOTICES.md",
  "config/crew-personas.yaml",
  "config/embedding-rag-policy.yaml",
  "config/evolution-policy.yaml",
  "config/stakeholder-boundaries.yaml",
  "references/bundled-skill-index.md",
  "references/workflow-sop-library.md",
  "references/skill-dependency-registry.md",
  "references/subagent-invocation-contract.md",
  "references/subagent-memory-runtime-contract.md",
  "references/project-asset-pack.md",
  "references/project-memory-index-architecture.md",
  "references/structured-review-loop.md",
  "references/semantic-stage-router.md",
  "references/embedding-rag-adapter.md",
  "references/evaluation-metrics.md",
  "references/host-runtime-compliance.md",
  "references/runtime-adapter-contract.md",
  "references/coze-runtime-blueprint.md",
  "references/workflow-implementation-coverage-v0.md",
  "references/workflow-implementation-coverage-v0.yaml",
  "integrations/coze/workflow-blueprint.yaml",
  "integrations/coze/runtime-plugin-openapi.yaml",
  "integrations/coze/sub-bot-bindings.example.yaml",
  "integrations/coze/database-schema.yaml",
  "integrations/coze/workflow-node-map.yaml",
  "integrations/coze/Dockerfile",
  "integrations/coze/docker-compose.yml",
  "integrations/coze/.env.example",
  "integrations/coze/deploy.md",
  "runtime/README.md",
  "runtime/create_demo_vault.rb",
  "runtime/db/embedding-rag-schema.sql",
  "runtime/db/schema.sql",
  "runtime/pco_runtime.rb",
  "runtime/pco_coze_bridge.rb",
  "runtime/rag_store.rb",
  "runtime/embedding_provider.rb",
  "runtime/sop_embedding_index.rb",
  "runtime/stage_router.rb",
  "templates/agent-context-packet.yaml",
  "templates/project-state.json",
  "templates/project-workspace/project-home.md",
  "templates/project-workspace/artifact-index.yaml",
  "templates/project-workspace/timeline.md",
  "templates/project-workspace/decision-log.md",
  "templates/project-workspace/review-items.yaml",
  "templates/project-workspace/conflict-matrix.md",
  "templates/project-workspace/open-questions.md",
  "templates/project-workspace/artifact-diff.md",
  "templates/project-workspace/risk-log.md",
  "templates/project-workspace/next-actions.md",
  "templates/project-workspace/source-ledger.md",
  "templates/project-workspace/event-log.jsonl",
  "templates/project-workspace/agent-memory/README.md",
  "templates/project-workspace/checkpoints/README.md",
  "templates/project-workspace/export-manifest.yaml",
  "templates/adapters/host-note-adapter-prompt.md",
  "templates/artifacts/review-session.md",
  "templates/artifacts/acceptance-criteria.md",
  "templates/artifacts/test-scenario-library.md",
  "tests/evaluation-test-plan.md",
  "tests/prompt-eval-cases.yaml",
  "tests/external-benchmark-cases.yaml",
  "tests/manual-score-cases.yaml",
  "tests/badcase-loop-50.md",
  "tests/test-ledger.md",
  "tests/test-ledger-schema.sql",
  "tests/run-external-benchmark.rb",
  "tests/run-embedding-rag-dry-run.rb",
  "tests/run-rag-ingestion-contract.rb",
  "tests/run-local-open-source-embedding-provider-contract.rb",
  "tests/run-routing-eval.rb",
  "tests/run-review-loop-e2e.rb",
  "tests/run-coze-runtime-bridge-smoke.rb",
  "tests/run-persistent-sop-vector-index.rb",
  "tests/run-runtime-smoke.rb",
  "tests/run-sop-e2e-smoke.rb",
  "tests/run-loop-50-cases.rb"
]

required_files.each do |relative_path|
  path = File.join(skill_root, relative_path)
  errors << "Missing required file: #{relative_path}" unless File.exist?(path)
end

skill_entry = File.read(File.join(skill_root, "SKILL.md"))
errors << "SKILL.md missing Runtime Preflight section" unless skill_entry.include?("## Runtime Preflight")
errors << "SKILL.md missing runtime_not_connected guard" unless skill_entry.include?("runtime_not_connected")
errors << "SKILL.md missing blocked_runtime_preflight guard" unless skill_entry.include?("blocked_runtime_preflight")
errors << "SKILL.md missing host runtime compliance reference" unless skill_entry.include?("host-runtime-compliance.md")

runtime_contract = File.read(File.join(skill_root, "references", "runtime-adapter-contract.md"))
errors << "runtime adapter contract missing route trace requirement" unless runtime_contract.include?("routing/stage-route-decision.jsonl")
errors << "runtime adapter contract missing runtime preflight downgrade" unless runtime_contract.include?("blocked_runtime_preflight")
errors << "runtime adapter contract missing real embedding env gate" unless runtime_contract.include?("PCO_REQUIRE_REAL_EMBEDDING")

coze_blueprint = File.read(File.join(skill_root, "references", "coze-runtime-blueprint.md"))
errors << "coze blueprint missing runtime_not_connected guard" unless coze_blueprint.include?("runtime_not_connected")
errors << "coze blueprint missing Runtime Preflight node" unless coze_blueprint.include?("Runtime Preflight")

host_compliance = File.read(File.join(skill_root, "references", "host-runtime-compliance.md"))
%w[real_embedding_provider subagent_delegate runtime_not_connected invalid_for_gate TF-IDF].each do |phrase|
  errors << "host runtime compliance missing #{phrase}" unless host_compliance.include?(phrase)
end

coze_yaml = YAML.load_file(File.join(skill_root, "integrations", "coze", "workflow-blueprint.yaml"))
errors << "coze workflow missing capability_handshake" unless coze_yaml.key?("capability_handshake")
errors << "coze workflow missing embedding_recall node" unless Array(coze_yaml["workflow_nodes"]).any? { |node| node["key"] == "embedding_recall" }
errors << "coze workflow missing runtime_preflight node" unless Array(coze_yaml["workflow_nodes"]).any? { |node| node["key"] == "runtime_preflight" }
deployment_assets = coze_yaml["deployment_assets"] || {}
%w[runtime_bridge_entrypoint openapi_plugin_contract sub_bot_binding_template coze_database_schema workflow_node_map].each do |key|
  errors << "coze workflow missing deployment asset: #{key}" if deployment_assets[key].to_s.empty?
end

coze_openapi = YAML.load_file(File.join(skill_root, "integrations", "coze", "runtime-plugin-openapi.yaml"))
%w[/v1/handshake /v1/routes /v1/rag/ingest /v1/rag/retrieve /v1/turns /v1/reviews/callback /v1/gates/finalize].each do |path|
  errors << "coze OpenAPI missing path: #{path}" unless (coze_openapi["paths"] || {}).key?(path)
end
errors << "coze OpenAPI missing bearer auth" unless coze_openapi.dig("components", "securitySchemes", "bearerAuth", "scheme") == "bearer"

coze_node_map = YAML.load_file(File.join(skill_root, "integrations", "coze", "workflow-node-map.yaml"))
node_keys = Array(coze_node_map.dig("workflow", "nodes")).map { |node| node["key"] }
%w[capability_handshake domain_and_sop_route turn_and_artifact_writer sub_bot_fan_out real_review_callback stage_gate_finalizer].each do |node_key|
  errors << "coze node map missing node: #{node_key}" unless node_keys.include?(node_key)
end

bridge = File.read(File.join(skill_root, "runtime", "pco_coze_bridge.rb"))
%w[PCO_RUNTIME_TOKEN record_real_review_callback finalize-stage-gate standard_sop route_decision_id runtime_agent_id].each do |phrase|
  errors << "coze runtime bridge missing #{phrase}" unless bridge.include?(phrase)
end

runtime_implementation = File.read(File.join(skill_root, "runtime", "pco_runtime.rb"))
%w[prepare_external_review finalize_stage_gate context_packet_quality persona_injection_status rag_ingest rag_retrieve].each do |phrase|
  errors << "runtime missing external Coze review guard: #{phrase}" unless runtime_implementation.include?(phrase)
end

rag_store = File.read(File.join(skill_root, "runtime", "rag_store.rb"))
%w[PersistentRagStore semantic_structured_overlap rag_ingestion_jobs embedding_retrieval_events consent_ref sqlite_json_cosine_fallback].each do |phrase|
  errors << "persistent RAG store missing #{phrase}" unless rag_store.include?(phrase)
end

bundled_skill_dir = File.join(skill_root, "third_party", "skills")
bundled_skill_files = Dir[File.join(bundled_skill_dir, "*", "SKILL.md")]
errors << "Missing bundled third-party skill directory: third_party/skills" unless Dir.exist?(bundled_skill_dir)
errors << "Expected at least 30 bundled third-party skills, found #{bundled_skill_files.length}" if bundled_skill_files.length < 30

bundled_index_path = File.join(skill_root, "references", "bundled-skill-index.md")
bundled_index = File.exist?(bundled_index_path) ? File.read(bundled_index_path) : ""
indexed_skill_dirs = bundled_index.scan(/^\|\s*`[^`]+`\s*\|\s*`(third_party\/skills\/[^`]+)`/).flatten.uniq
indexed_skill_dirs.each do |relative_dir|
  dir = File.join(skill_root, relative_dir)
  errors << "Bundled skill index points to missing directory: #{relative_dir}" unless Dir.exist?(dir)
  errors << "Bundled skill index points to directory without SKILL.md: #{relative_dir}" unless File.exist?(File.join(dir, "SKILL.md"))
end
errors << "Bundled skill index has fewer entries than bundled skills" if indexed_skill_dirs.length < bundled_skill_files.length

state = JSON.parse(File.read(File.join(skill_root, "templates", "project-state.json")))
%w[agent_invocation_ledger memory_delta_queue config memory project_asset_pack].each do |key|
  errors << "project-state.json missing #{key}" unless state.key?(key)
end

asset_pack = state["project_asset_pack"] || {}
%w[project_home artifact_index timeline decision_log review_items conflict_matrix open_questions artifact_diff risk_log next_actions source_ledger event_log agent_memory checkpoints export_manifest].each do |key|
  errors << "project_asset_pack missing #{key}" unless asset_pack.key?(key)
end

packet = YAML.load_file(File.join(skill_root, "templates", "agent-context-packet.yaml"))
%w[invocation artifact review memory_snapshot output_contract].each do |key|
  errors << "agent-context-packet.yaml missing #{key}" unless packet.key?(key)
end

prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
prompt_eval = YAML.load_file(prompt_eval_path)
cases = prompt_eval["cases"] || []
errors << "prompt-eval-cases.yaml should contain exactly 44 cases, found #{cases.length}" unless cases.length == 44
stage_ids = cases.map { |test_case| test_case["stage_id"] }.compact
errors << "prompt-eval-cases.yaml has duplicate stage_id entries" unless stage_ids.uniq.length == stage_ids.length
required_case_keys = %w[case_id stage_id macro_stage user_input source expected]
required_expected_keys = %w[product_crew_os_applies primary_skill fallback_skill required_roles required_artifacts stage_gate]
cases.each do |test_case|
  case_label = test_case["case_id"] || test_case["stage_id"] || "unknown"
  required_case_keys.each do |key|
    errors << "prompt eval case #{case_label} missing #{key}: #{test_case.inspect}" unless test_case.key?(key)
  end
  expected = test_case["expected"] || {}
  required_expected_keys.each do |key|
    errors << "prompt eval case #{case_label} missing expected.#{key}" unless expected.key?(key)
  end
end

if errors.empty?
  puts "validate-package: PASS"
  puts "scenarios: #{actual.length}"
else
  warn "validate-package: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
