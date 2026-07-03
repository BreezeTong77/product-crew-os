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
  "config/evolution-policy.yaml",
  "config/stakeholder-boundaries.yaml",
  "references/bundled-skill-index.md",
  "references/workflow-sop-library.md",
  "references/skill-dependency-registry.md",
  "references/subagent-invocation-contract.md",
  "references/subagent-memory-runtime-contract.md",
  "references/project-asset-pack.md",
  "references/project-memory-index-architecture.md",
  "references/evaluation-metrics.md",
  "references/runtime-adapter-contract.md",
  "references/coze-runtime-blueprint.md",
  "integrations/coze/workflow-blueprint.yaml",
  "runtime/README.md",
  "runtime/create_demo_vault.rb",
  "runtime/db/schema.sql",
  "runtime/pco_runtime.rb",
  "templates/agent-context-packet.yaml",
  "templates/project-state.json",
  "templates/project-workspace/project-home.md",
  "templates/project-workspace/artifact-index.yaml",
  "templates/project-workspace/timeline.md",
  "templates/project-workspace/decision-log.md",
  "templates/project-workspace/review-items.yaml",
  "templates/project-workspace/risk-log.md",
  "templates/project-workspace/next-actions.md",
  "templates/project-workspace/source-ledger.md",
  "templates/project-workspace/event-log.jsonl",
  "templates/project-workspace/agent-memory/README.md",
  "templates/project-workspace/checkpoints/README.md",
  "templates/project-workspace/export-manifest.yaml",
  "templates/adapters/host-note-adapter-prompt.md",
  "templates/artifacts/acceptance-criteria.md",
  "templates/artifacts/test-scenario-library.md",
  "tests/evaluation-test-plan.md",
  "tests/prompt-eval-cases.yaml",
  "tests/run-external-benchmark.rb",
  "tests/run-runtime-smoke.rb",
  "tests/run-sop-e2e-smoke.rb"
]

required_files.each do |relative_path|
  path = File.join(skill_root, relative_path)
  errors << "Missing required file: #{relative_path}" unless File.exist?(path)
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
%w[project_home artifact_index timeline decision_log review_items risk_log next_actions source_ledger event_log agent_memory checkpoints export_manifest].each do |key|
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
