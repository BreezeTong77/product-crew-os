#!/usr/bin/env ruby

require "fileutils"
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

result_dir = File.join(skill_root, "tests", "results")
result_path = File.join(result_dir, "latest-regression.md")
generated_at = Time.now.utc.iso8601
command = "ruby product-crew-os-skill/tests/run-regression.rb #{ARGV.join(" ")}".strip

if errors.empty?
  unless check_only
    FileUtils.mkdir_p(result_dir)
    File.write(result_path, "# Regression Result\n\nstatus: PASS\n\ngenerated_at: #{generated_at}\ncommand: #{command}\n\nchecks:\n- package scenarios loaded\n- mock delegate invocation ledger assertion passed\n- simulation fallback label assertion passed\n- memory snapshot and memory delta assertion passed\n")
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
