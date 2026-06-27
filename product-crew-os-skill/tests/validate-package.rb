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
  "config/crew-personas.yaml",
  "config/evolution-policy.yaml",
  "config/stakeholder-boundaries.yaml",
  "references/workflow-sop-library.md",
  "references/subagent-invocation-contract.md",
  "references/subagent-memory-runtime-contract.md",
  "templates/agent-context-packet.yaml",
  "templates/project-state.json",
  "templates/artifacts/acceptance-criteria.md",
  "templates/artifacts/test-scenario-library.md"
]

required_files.each do |relative_path|
  path = File.join(skill_root, relative_path)
  errors << "Missing required file: #{relative_path}" unless File.exist?(path)
end

state = JSON.parse(File.read(File.join(skill_root, "templates", "project-state.json")))
%w[agent_invocation_ledger memory_delta_queue config memory].each do |key|
  errors << "project-state.json missing #{key}" unless state.key?(key)
end

packet = YAML.load_file(File.join(skill_root, "templates", "agent-context-packet.yaml"))
%w[invocation artifact review memory_snapshot output_contract].each do |key|
  errors << "agent-context-packet.yaml missing #{key}" unless packet.key?(key)
end

if errors.empty?
  puts "validate-package: PASS"
  puts "scenarios: #{actual.length}"
else
  warn "validate-package: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
