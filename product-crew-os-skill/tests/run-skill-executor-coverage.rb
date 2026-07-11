#!/usr/bin/env ruby

require "yaml"

skill_root = File.expand_path("..", __dir__)
cases = YAML.load_file(File.join(skill_root, "tests", "prompt-eval-cases.yaml")).fetch("cases")
config = YAML.load_file(File.join(skill_root, "config", "skill-executor-registry.yaml"))
registry = config.fetch("skills")
bundled = File.read(File.join(skill_root, "references", "bundled-skill-index.md")).scan(/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`/).to_h

skills = cases.flat_map do |test_case|
  expected = test_case.fetch("expected")
  [expected.fetch("primary_skill"), *expected.fetch("fallback_skill").to_s.split(/\s*\/\s*/)]
end.map(&:strip).reject(&:empty?).uniq

unresolved = skills.reject do |skill|
  registry.key?(skill) || bundled.key?(skill)
end
abort "unresolved routed skills: #{unresolved.join(', ')}" unless unresolved.empty?

counts = Hash.new(0)
skills.each do |skill|
  driver = registry.dig(skill, "driver") || "ollama_prompt"
  counts[driver] += 1
end

puts "run-skill-executor-coverage: PASS"
puts "routed_skills=#{skills.length} #{counts.sort.map { |driver, count| "#{driver}=#{count}" }.join(' ')}"
