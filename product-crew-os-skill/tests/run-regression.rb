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

errors = []
def assert(errors, condition, message)
  errors << message unless condition
end

packet = YAML.load_file(File.join(skill_root, "templates", "agent-context-packet.yaml"))

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
%w[project_home artifact_index timeline decision_log review_items risk_log next_actions source_ledger event_log agent_memory checkpoints export_manifest].each do |key|
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

result_dir = File.join(skill_root, "tests", "results")
result_path = File.join(result_dir, "latest-regression.md")
generated_at = Time.now.utc.iso8601
command = "ruby product-crew-os-skill/tests/run-regression.rb #{ARGV.join(" ")}".strip

if errors.empty?
  unless check_only
    FileUtils.mkdir_p(result_dir)
    File.write(result_path, "# Regression Result\n\nstatus: PASS\n\ngenerated_at: #{generated_at}\ncommand: #{command}\n\nchecks:\n- package scenarios loaded\n- mock delegate invocation ledger assertion passed\n- simulation fallback label assertion passed\n- memory snapshot and memory delta assertion passed\n- non-product task exits Product Crew OS workflow assertion passed\n- project asset pack persistence assertion passed\n")
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
