#!/usr/bin/env ruby

require "yaml"

skill_root = File.expand_path("..", __dir__)
installed_root = ENV.fetch("PCO_CODEX_SKILL_ROOT", File.join(Dir.home, ".codex", "skills", "product-crew-os"))
cases = YAML.load_file(File.join(skill_root, "tests", "prompt-eval-cases.yaml")).fetch("cases")
bundled = File.read(File.join(skill_root, "references", "bundled-skill-index.md")).scan(/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`/).to_h
registry = YAML.load_file(File.join(skill_root, "config", "skill-executor-registry.yaml")).fetch("skills")
skills = cases.flat_map do |test_case|
  expected = test_case.fetch("expected")
  [expected.fetch("primary_skill"), *expected.fetch("fallback_skill").to_s.split(/\s*\/\s*/)]
end.map(&:strip).reject(&:empty?).uniq

bundled_skills = skills.select { |skill| bundled.key?(skill) }
missing_installed = bundled_skills.reject { |skill| File.file?(File.join(installed_root, bundled.fetch(skill), "SKILL.md")) }
missing_fallback_policy = (skills - bundled_skills).reject { |skill| registry.key?(skill) }
policy = File.read(File.join(skill_root, "SKILL.md"))

abort "bundled Codex Skills missing from installed package: #{missing_installed.join(', ')}" unless missing_installed.empty?
abort "non-bundled fallbacks missing policy: #{missing_fallback_policy.join(', ')}" unless missing_fallback_policy.empty?
abort "Codex native Skill rule missing from Product Crew OS SKILL.md" unless policy.include?("Codex Native Skill Execution") && policy.include?("host_native_executed")

puts "run-codex-host-skill-availability: PASS"
puts "routed_skills=#{skills.length} codex_native=#{bundled_skills.length} connector_or_missing=#{skills.length - bundled_skills.length}"
