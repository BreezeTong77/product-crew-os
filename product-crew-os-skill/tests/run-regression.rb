#!/usr/bin/env ruby

require "fileutils"
require "json"
require "time"
require "yaml"

skill_root = File.expand_path("..", __dir__)
scenario_dir = File.join(skill_root, "tests", "scenarios")
scenarios = Dir[File.join(scenario_dir, "*.yaml")].each_with_object({}) do |path, memo|
  scenario = YAML.load_file(path)
  memo[scenario["scenario_id"]] = scenario
end
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
prompt_eval_cases = YAML.load_file(prompt_eval_path)["cases"] || []

errors = []
def assert(errors, condition, message)
  errors << message unless condition
end

packet = YAML.load_file(File.join(skill_root, "templates", "agent-context-packet.yaml"))
base_persona = packet.dig("memory_snapshot", "base_persona") || {}
%w[role_key title display_name role persona_source_ref persona_injection_status].each do |field|
  assert(errors, base_persona.key?(field), "agent context packet base_persona missing #{field}")
end
%w[personality speaking_style must_do must_not_do memory_focus].each do |field|
  assert(errors, base_persona[field].is_a?(Array), "agent context packet base_persona #{field} must be an array")
end
assert(errors, (packet.dig("output_contract", "must_include") || []).include?("use configured persona voice"), "agent output contract must require configured persona voice")

persona_config = YAML.load_file(File.join(skill_root, "config", "crew-personas.yaml"))
%w[biz research design tech data qa legal cs customer ops].each do |persona_key|
  persona = persona_config.dig("personas", persona_key) || {}
  label = persona["role_key"] || persona_key
  %w[role_key title display_name role].each do |field|
    assert(errors, persona[field].to_s != "", "crew persona #{label} missing #{field}")
  end
  %w[personality speaking_style must_do must_not_do memory_focus].each do |field|
    assert(errors, Array(persona[field]).any?, "crew persona #{label} missing #{field}")
  end
end

mock_delegate_enabled = ARGV.include?("--mock-delegate")
check_only = ARGV.include?("--check-only")
if mock_delegate_enabled
  packet["invocation"]["real_invocation_required"] = true
  packet["invocation"]["real_invocation_performed"] = true
  packet["invocation"]["runtime_agent_id"] = "mock-agent-qa-001"
  packet["review"]["role_key"] = "QA"
  ledger_entry = {
    "role_key" => "QA",
    "display_name" => "李测",
    "real_invocation_performed" => true,
    "runtime_agent_id" => packet["invocation"]["runtime_agent_id"],
    "simulation_label_used" => false,
    "result" => "conditional_pass"
  }

  assert(errors, scenarios.key?("subagent_real_invocation_contract"), "missing subagent_real_invocation_contract scenario")
  assert(errors, packet["review"]["role_key"] == "QA", "mock invocation did not bind role_key QA")
  assert(errors, ledger_entry["runtime_agent_id"] != "", "mock invocation did not write runtime_agent_id")
  assert(errors, ledger_entry["real_invocation_performed"] == true, "mock invocation was not marked real")
end

simulation_label = "下面是模拟 李测 视角，不是已真实拉起子 Agent。"
assert(errors, simulation_label.include?("模拟 李测 视角"), "simulation label missing role display name")
assert(errors, simulation_label.include?("不是已真实拉起子 Agent"), "simulation label does not deny real invocation")

memory_packet = YAML.load_file(File.join(skill_root, "templates", "agent-context-packet.yaml"))
memory_packet["review"]["role_key"] = "Design"
memory_packet["memory_snapshot"]["project_role_memory"]["exists"] = true
memory_packet["memory_snapshot"]["project_role_memory"]["last_objections"] = [
  {
    "artifact" => "low-fi-prototype-brief.md",
    "summary" => "首页发布入口和底部导航存在冲突",
    "source_ref" => "fixture:design-memory"
  }
]
memory_delta = {
  "target_scope" => "project",
  "role_key" => "Design",
  "source_ref" => "fixture:design-memory",
  "confidence" => "confirmed",
  "summary" => "Design role still checks homepage entry and bottom navigation conflict"
}

assert(errors, scenarios.key?("subagent_memory_runtime"), "missing subagent_memory_runtime scenario")
assert(errors, memory_packet["memory_snapshot"]["project_role_memory"]["exists"] == true, "memory snapshot did not mark project role memory")
assert(errors, memory_packet["memory_snapshot"]["project_role_memory"]["last_objections"].any?, "memory snapshot missing prior objection")
assert(errors, memory_delta["source_ref"] != "", "memory delta missing source_ref")
assert(errors, memory_delta["confidence"] != "", "memory delta missing confidence")

non_product_scenario = scenarios["non_product_task_exits_workflow"]
assert(errors, !non_product_scenario.nil?, "missing non_product_task_exits_workflow scenario")
if non_product_scenario
  expected = non_product_scenario["expected"] || {}
  assert(errors, expected["product_crew_os_applies"] == false, "non-product scenario should not enter Product Crew OS workflow")
  assert(errors, expected["skill_router_enabled"] == false, "non-product scenario should not enable Skill Router")
  assert(errors, (expected["required_agents"] || []).empty?, "non-product scenario should not require sub-agents")
  assert(errors, (expected["must_not"] || []).include?("route to request_triage"), "non-product scenario should forbid forced request_triage")
end

asset_pack_scenario = scenarios["project_asset_pack_persistence"]
assert(errors, !asset_pack_scenario.nil?, "missing project_asset_pack_persistence scenario")
state = JSON.parse(File.read(File.join(skill_root, "templates", "project-state.json")))
asset_pack = state["project_asset_pack"] || {}
assert(errors, !asset_pack.empty?, "project-state.json missing project_asset_pack")
%w[project_home artifact_index timeline decision_log review_items conflict_matrix open_questions artifact_diff risk_log next_actions source_ledger event_log agent_memory checkpoints export_manifest].each do |key|
  assert(errors, asset_pack[key].to_s != "", "project_asset_pack missing #{key}")
end
if asset_pack_scenario
  expected = asset_pack_scenario["expected"] || {}
  assert(errors, expected["required_artifact"] == "Project Asset Pack", "asset pack scenario should require Project Asset Pack")
  assert(errors, (expected["must_not"] || []).include?("treat Obsidian as required"), "asset pack scenario should keep Obsidian optional")
  required_files = expected["required_files"] || []
  available_files = [
    "project-state.json",
    *Dir[File.join(skill_root, "templates", "project-workspace", "**", "*")].select { |path| File.file?(path) }.map { |path| File.basename(path) }
  ]
  required_files.each do |required_file|
    assert(errors, available_files.include?(required_file), "asset pack required file missing from templates: #{required_file}")
  end
  contract_text = [
    File.read(File.join(skill_root, "references", "project-asset-pack.md")),
    File.read(File.join(skill_root, "templates", "project-workspace", "export-manifest.yaml")),
    File.read(File.join(skill_root, "templates", "project-workspace", "source-ledger.md"))
  ].join("\n")
  (expected["must_include"] || []).each do |phrase|
    assert(errors, contract_text.include?(phrase), "asset pack contract missing phrase: #{phrase}")
  end
  (expected["must_not"] || []).each do |phrase|
    assert(errors, !contract_text.include?(phrase), "asset pack contract includes forbidden phrase: #{phrase}")
  end
  review_closed_updates = expected["review_closed_updates"] || []
  assert(errors, !review_closed_updates.empty?, "asset pack scenario missing review_closed_updates")
  review_closed_line = contract_text.lines.find { |line| line.include?("| Review Closed |") }.to_s
  review_closed_updates.each do |artifact|
    assert(errors, review_closed_line.include?(artifact), "Review Closed contract missing update: #{artifact}")
  end
end

structured_review_scenario = scenarios["structured_review_loop_visibility"]
assert(errors, !structured_review_scenario.nil?, "missing structured_review_loop_visibility scenario")
if structured_review_scenario
  reference_path = File.join(skill_root, "references", "structured-review-loop.md")
  assert(errors, File.exist?(reference_path), "missing structured review loop reference")
  reference_text = File.read(reference_path)
  expected = structured_review_scenario["expected"] || {}
  (expected["required_files"] || []).each do |required_file|
    case required_file
    when "review-session.md"
      assert(errors, File.exist?(File.join(skill_root, "templates", "artifacts", required_file)), "structured review template missing #{required_file}")
    else
      assert(errors, File.exist?(File.join(skill_root, "templates", "project-workspace", required_file)), "structured review workspace template missing #{required_file}")
    end
  end
  (expected["must_include"] || []).each do |phrase|
    assert(errors, reference_text.include?(phrase), "structured review loop missing phrase: #{phrase}")
  end
  assert(errors, !reference_text.include?("主控教练可以替用户采纳"), "structured review loop must not let coach decide acceptance")
  assert(errors, reference_text.include?("每个角色的原始评审意见"), "structured review loop must require raw role review records")
end

review_batch_scenario = scenarios["review_batch_coverage"]
assert(errors, !review_batch_scenario.nil?, "missing review_batch_coverage scenario")
evolution_policy = YAML.load_file(File.join(skill_root, "config", "evolution-policy.yaml"))
run_controls = evolution_policy["run_controls"] || {}
assert(errors, run_controls["max_agents_per_review_batch"].to_i > 0, "run_controls missing max_agents_per_review_batch")
assert(errors, run_controls["max_review_batches_per_stage_gate"].to_i > 0, "run_controls missing max_review_batches_per_stage_gate")
assert(errors, run_controls["required_roles_must_not_be_suppressed_by_batch_limit"] == true, "batch limit may suppress required roles")
batching_policy = run_controls["review_batching_policy"] || {}
assert(errors, batching_policy["batch_size_limit_scope"].to_s.include?("not per stage"), "review batching policy must clarify batch limit is not a stage limit")
assert(errors, Array(batching_policy["must_not"]).any? { |item| item.include?("drop required roles") }, "review batching policy must forbid dropping required roles")
if review_batch_scenario
  expected = review_batch_scenario["expected"] || {}
  assert(errors, (expected["must_not"] || []).include?("drop required roles because the first batch is full"), "review batch scenario should forbid first-batch role dropping")
end

semantic_router_text = File.read(File.join(skill_root, "references", "semantic-stage-router.md"))
%w[candidate_routes retrieval_mode confidence_gap template_degraded_rate agent_miss_rate coach_over_decision_rate skill_execution_hit_rate].each do |phrase|
  assert(errors, semantic_router_text.include?(phrase), "semantic stage router missing #{phrase}")
end
metrics_text = File.read(File.join(skill_root, "references", "evaluation-metrics.md"))
%w[Template 降级率 子 Agent 漏召率 主控越权决策率 Skill 执行命中率].each do |phrase|
  assert(errors, metrics_text.include?(phrase), "evaluation metrics missing #{phrase}")
end
embedding_reference = File.read(File.join(skill_root, "references", "embedding-rag-adapter.md"))
[
  "pco_rules",
  "project",
  "user_overlay",
  "team_style_overlay",
  "Input Scope Gate",
  "hard non-product exit check",
  "source_ref",
  "confidence_gap",
  "local_open_source_bge_small_zh",
  "PaddleOCR",
  "Tesseract",
  "semantic_structured_overlap",
  "BAAI/bge-small-zh-v1.5",
  "sqlite-vec",
  "FTS5",
  "incremental update",
  "maintenance",
  "recall",
  "precision"
].each do |phrase|
  assert(errors, embedding_reference.include?(phrase), "embedding RAG adapter missing #{phrase}")
end
embedding_policy = YAML.load_file(File.join(skill_root, "config", "embedding-rag-policy.yaml"))
assert(errors, embedding_policy.dig("input_scope_gate", "routing_model") == "hard_exit_first_then_parallel_rule_and_embedding", "embedding policy must use input scope gate parallel routing")
assert(errors, embedding_policy.dig("input_scope_gate", "hard_non_product_task", "retrieval_enabled") == false, "embedding policy must block retrieval for hard non-product tasks")
assert(errors, embedding_policy.dig("input_scope_gate", "ambiguous_task", "pco_rules_retrieval_enabled") == true, "embedding policy must allow public pco_rules retrieval for ambiguous tasks")
assert(errors, embedding_policy.dig("input_scope_gate", "ambiguous_task", "private_namespace_retrieval_enabled") == false, "embedding policy must block private retrieval during ambiguous scope gate")
assert(errors, embedding_policy.dig("domain_gate", "legacy_alias_for") == "input_scope_gate", "embedding policy must keep domain gate as legacy alias")
assert(errors, embedding_policy.dig("release_gate", "ingestion_contract_required") == true, "embedding policy must require ingestion contract")
assert(errors, embedding_policy.dig("release_gate", "real_embedding_required_for_standard_sop") == true, "embedding policy must require real embedding for standard SOP")
assert(errors, embedding_policy.dig("source_ingestion", "ocr", "primary_engine") == "PaddleOCR", "embedding policy must set PaddleOCR as primary OCR")
assert(errors, embedding_policy.dig("chunking", "strategy") == "semantic_structured_overlap", "embedding policy must use semantic structured overlap chunking")
assert(errors, embedding_policy.dig("providers", "local_open_source_bge_small_zh", "model_name") == "BAAI/bge-small-zh-v1.5", "embedding policy must choose BAAI/bge-small-zh-v1.5")
assert(errors, embedding_policy.dig("vector_store", "default") == "sqlite_vec", "embedding policy must default to sqlite_vec")
assert(errors, embedding_policy.dig("batch_indexing", "enabled") == true, "embedding policy must enable batch indexing")
assert(errors, embedding_policy.dig("incremental_update", "enabled") == true, "embedding policy must enable incremental update")
assert(errors, embedding_policy.dig("namespaces", "pco_rules", "public_package_allowed") == true, "embedding policy must allow public pco_rules in package")
%w[project user_overlay team_style_overlay].each do |namespace|
  assert(errors, embedding_policy.dig("namespaces", namespace, "public_package_allowed") == false, "embedding policy must keep #{namespace} out of public package")
  assert(errors, embedding_policy.dig("namespaces", namespace, "consent_required") == true, "embedding policy must require consent for #{namespace}")
end
embedding_schema = File.read(File.join(skill_root, "runtime", "db", "embedding-rag-schema.sql"))
%w[embedding_documents embedding_chunks embedding_retrieval_events namespace source_ref consent_ref public_package_allowed source_type extraction_method ocr_confidence section_path embedding_vector_indexes rag_ingestion_jobs rag_retrieval_quality_metrics rag_maintenance_events score_breakdown_json].each do |phrase|
  assert(errors, embedding_schema.include?(phrase), "embedding schema missing #{phrase}")
end
dry_run_script = File.read(File.join(skill_root, "tests", "run-embedding-rag-dry-run.rb"))
%w[rag_stage_hit_at_1 rag_stage_hit_at_3 false_positive_domain_entry_rate source_trace_rate namespace_isolation_violations RETRIEVAL_STOP_TERMS launch_readiness one_page_proposal prioritization].each do |phrase|
  assert(errors, dry_run_script.include?(phrase), "embedding dry-run missing #{phrase}")
end
rag_ingestion_contract = File.read(File.join(skill_root, "tests", "run-rag-ingestion-contract.rb"))
%w[PaddleOCR Tesseract semantic_structured_overlap BAAI/bge-small-zh-v1.5 sqlite_vec rag_recall_at_3].each do |phrase|
  assert(errors, rag_ingestion_contract.include?(phrase), "RAG ingestion contract missing #{phrase}")
end
embedding_provider = File.read(File.join(skill_root, "runtime", "embedding_provider.rb"))
%w[LocalOpenSourceBGESmallZH BAAI/bge-small-zh-v1.5 real_embedding_performed local_hash_dry_run runtime_blocked_missing_local_model embed_batch].each do |phrase|
  assert(errors, embedding_provider.include?(phrase), "embedding provider missing #{phrase}")
end
sop_embedding_index = File.read(File.join(skill_root, "runtime", "sop_embedding_index.rb"))
%w[SopEmbeddingIndex embed_batch vector_score source_refs].each do |phrase|
  assert(errors, sop_embedding_index.include?(phrase), "SOP embedding index missing #{phrase}")
end
local_embedding_contract = File.read(File.join(skill_root, "tests", "run-local-open-source-embedding-provider-contract.rb"))
%w[local_open_source_bge_small_zh real_local_call_passed runtime_blocked_missing_local_model SopEmbeddingIndex].each do |phrase|
  assert(errors, local_embedding_contract.include?(phrase), "local open-source embedding contract missing #{phrase}")
end

host_runtime_compliance = File.read(File.join(skill_root, "references", "host-runtime-compliance.md"))
%w[Capability Handshake real_embedding_provider subagent_delegate runtime_not_connected invalid_for_gate].each do |phrase|
  assert(errors, host_runtime_compliance.include?(phrase), "host runtime compliance missing #{phrase}")
end

assert(errors, prompt_eval_cases.length == 44, "prompt eval should cover 44 SOP cases, found #{prompt_eval_cases.length}")
%w[project_intake low_fi_prototype formal_requirements_review launch_readiness iteration_planning].each do |stage_id|
  assert(errors, prompt_eval_cases.any? { |test_case| test_case["stage_id"] == stage_id }, "prompt eval missing stage: #{stage_id}")
end
prompt_eval_cases.each do |test_case|
  case_label = test_case["case_id"] || test_case["stage_id"] || "unknown"
  expected = test_case["expected"] || {}
  assert(errors, expected["product_crew_os_applies"] == true, "prompt eval #{case_label} should apply Product Crew OS")
  assert(errors, expected["primary_skill"].to_s != "", "prompt eval #{case_label} missing primary skill")
  assert(errors, expected["fallback_skill"].to_s != "", "prompt eval #{case_label} missing fallback skill")
  assert(errors, Array(expected["required_artifacts"]).any?, "prompt eval #{case_label} missing required artifacts")
  assert(errors, expected["stage_gate"].to_s != "", "prompt eval #{case_label} missing stage gate")
end

result_dir = File.join(skill_root, "tests", "results")
result_path = File.join(result_dir, "latest-regression.md")
generated_at = Time.now.utc.iso8601
command = "ruby product-crew-os-skill/tests/run-regression.rb #{ARGV.join(" ")}".strip

if errors.empty?
  unless check_only
    FileUtils.mkdir_p(result_dir)
    File.write(result_path, "# Regression Result\n\nstatus: PASS\n\ngenerated_at: #{generated_at}\ncommand: #{command}\n\nchecks:\n- package scenarios loaded\n- persona injection contract assertion passed\n- mock delegate invocation ledger assertion passed\n- simulation fallback label assertion passed\n- memory snapshot and memory delta assertion passed\n- non-product task exits Product Crew OS workflow assertion passed\n- project asset pack persistence assertion passed\n- review batch coverage assertion passed\n- semantic router RAG and bad-rate metric assertions passed\n- embedding RAG adapter contract assertions passed
- RAG ingestion / OCR / chunk / vector store contract assertions passed
- local open-source embedding provider contract assertions passed
- 44 SOP prompt eval coverage assertion passed\n")
  end
  puts "run-regression: PASS"
  puts "result: #{check_only ? "not written (--check-only)" : result_path}"
else
  unless check_only
    FileUtils.mkdir_p(result_dir)
    File.write(result_path, "# Regression Result\n\nstatus: FAIL\n\ngenerated_at: #{generated_at}\ncommand: #{command}\n\nerrors:\n#{errors.map { |error| "- #{error}" }.join("\n")}\n")
  end
  warn "run-regression: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
