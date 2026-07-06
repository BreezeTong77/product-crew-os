#!/usr/bin/env ruby

require "fileutils"
require "time"
require "yaml"
require_relative "../runtime/stage_router"

skill_root = File.expand_path("..", __dir__)
benchmark_dir = ARGV[0] || File.join(skill_root, "third_party", "skills", "pm-workbench", "benchmark")
output_dir = ARGV[1] || File.join(skill_root, "tests", "results", "external-benchmark-#{Time.now.strftime("%Y%m%d-%H%M%S")}")
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")

unless Dir.exist?(benchmark_dir)
  warn "benchmark directory not found: #{benchmark_dir}"
  exit 1
end

unless File.exist?(prompt_eval_path)
  warn "prompt eval cases not found: #{prompt_eval_path}"
  exit 1
end

def extract_scenarios(path)
  scenarios = []
  current = nil
  in_prompt = false

  File.readlines(path, chomp: true).each do |line|
    if (match = line.match(/^#+\s+Scenario\s+(\d+)\s+[—-]\s+(.+)$/))
      scenarios << current if current && !current[:prompt].empty?
      current = {
        "source_file" => File.basename(path),
        "source_scenario" => match[1].to_i,
        "title" => match[2].strip,
        :prompt => []
      }
      in_prompt = false
      next
    end

    next unless current

    if line.match?(/^#+\s+Prompt\s*$/)
      in_prompt = true
      next
    end

    if in_prompt
      if line.start_with?(">")
        current[:prompt] << line.sub(/^>\s?/, "").strip
      elsif !line.strip.empty? && !current[:prompt].empty?
        in_prompt = false
      end
    end
  end

  scenarios << current if current && !current[:prompt].empty?
  scenarios.map do |scenario|
    scenario["prompt"] = scenario.delete(:prompt).join(" ").strip
    scenario
  end
end

def classify_stage(prompt)
  text = prompt.downcase

  operational_action = text.match?(/\bmove all\b.*\btasks?\b/) ||
                       text.match?(/\bmove\b.*\btasks?\b.*\bto\b/) ||
                       text.match?(/\badd a new task\b/) ||
                       text.match?(/\bcreate a task\b/) ||
                       text.match?(/\bassign\b.*\btasks?\b/) ||
                       text.match?(/\bupdate\b.*\btasks?\b/) ||
                       text.match?(/\btasks?\b.*\bto in review\b/)

  return nil if operational_action

  rules = [
    [/operating review|activation is up|support tickets|quality complaints|mixed signals/, "launch_monitoring"],
    [/one-page update|exec summary|resource ask|frontend engineer|recommend we do not scale marketing|leadership.*update/, "one_page_proposal"],
    [/postmortem|what happened|what we got wrong|change next time|lessons/, "post_launch_review"],
    [/launch readiness|launch recommendation|launch date|campaign lead time|support flows are not ready|confident answer by tomorrow|go\/no-go|rollout|release/, "launch_readiness"],
    [/only have room|only really do 3|top-3|above the line|below-the-line|candidate items|what should wait/, "prioritization"],
    [/daily .*fortune|daily .*luck|fortune card|luck card|gimmick|shareable moments|roadmap space/, "value_sizing"],
    [/roadmap|next two quarters|next quarter|quarter objective/, "iteration_planning"],
    [/two credible ways|option a|option b|compare the two|recommend a path/, "solution_exploration"],
    [/founder|investor|runway|4 weeks|8-10 weeks|broad .*copilot|workspace memory|help me decide/, "solution_exploration"],
    [/wow factor|premium|alive|competitors|not convinced|what problem|figure out what that actually means/, "problem_definition"]
  ]

  matched = rules.find { |pattern, _stage| text.match?(pattern) }
  matched ? matched[1] : "request_triage"
end

prompt_eval = YAML.load_file(prompt_eval_path)
cases_by_stage = prompt_eval.fetch("cases").each_with_object({}) do |entry, index|
  index[entry.fetch("stage_id")] ||= entry
end
router = SemanticStageRouter.new(prompt_eval_path: prompt_eval_path)

source_files = [
  File.join(benchmark_dir, "scenarios.md"),
  File.join(benchmark_dir, "high-pressure-acceptance-suite.md")
].select { |path| File.exist?(path) }

external_cases = source_files.flat_map { |path| extract_scenarios(path) }

routed_cases = external_cases.map do |external_case|
  route = router.route(external_case.fetch("prompt"))
  stage_id = route["stage_id"]
  reference = stage_id && cases_by_stage[stage_id]

  expected = reference ? reference.fetch("expected") : {}
  {
    "source_file" => external_case.fetch("source_file"),
    "source_scenario" => external_case.fetch("source_scenario"),
    "title" => external_case.fetch("title"),
    "prompt" => external_case.fetch("prompt"),
    "routed_stage_id" => stage_id,
    "macro_stage" => reference && reference["macro_stage"],
    "primary_skill" => expected["primary_skill"],
    "fallback_skill" => expected["fallback_skill"],
    "required_roles" => expected["required_roles"] || [],
    "required_artifacts" => expected["required_artifacts"] || [],
    "stage_gate" => expected["stage_gate"],
    "route_status" => if route["route_status"] == "domain_exit"
                         "domain_exit"
                       elsif reference
                         "mapped"
                       else
                         "unmapped"
                       end
  }
end

mapped_cases = routed_cases.select { |entry| entry["route_status"] == "mapped" }
domain_exit_cases = routed_cases.select { |entry| entry["route_status"] == "domain_exit" }
coverage = {
  "source" => benchmark_dir,
  "source_files" => source_files.map { |path| File.basename(path) },
  "total_external_cases" => external_cases.length,
  "mapped_cases" => mapped_cases.length,
  "domain_exit_cases" => domain_exit_cases.length,
  "unmapped_cases" => routed_cases.length - mapped_cases.length - domain_exit_cases.length,
  "unique_stages" => mapped_cases.map { |entry| entry["routed_stage_id"] }.uniq.sort,
  "unique_macro_stages" => mapped_cases.map { |entry| entry["macro_stage"] }.compact.uniq.sort,
  "unique_primary_skills" => mapped_cases.map { |entry| entry["primary_skill"] }.compact.uniq.sort,
  "roles_touched" => mapped_cases.flat_map { |entry| entry["required_roles"] }.uniq.sort
}

required_smoke_stages = %w[
  problem_definition
  value_sizing
  prioritization
  one_page_proposal
  post_launch_review
]
missing_smoke_stages = required_smoke_stages - coverage.fetch("unique_stages")
positive_suite = mapped_cases.any?
negative_suite = domain_exit_cases.any? && mapped_cases.empty?

summary = {
  "status" => external_cases.any? &&
              coverage.fetch("unmapped_cases").zero? &&
              ((positive_suite && missing_smoke_stages.empty?) || negative_suite) ? "PASS" : "WARN",
  "missing_smoke_stages" => missing_smoke_stages,
  "coverage" => coverage,
  "routed_cases" => routed_cases
}

FileUtils.mkdir_p(output_dir)
File.write(File.join(output_dir, "external-benchmark-routes.yaml"), summary.to_yaml)

report_lines = []
report_lines << "# External Benchmark Run Report"
report_lines << ""
report_lines << "Source: `#{benchmark_dir}`"
report_lines << "Status: `#{summary.fetch("status")}`"
report_lines << ""
report_lines << "## Coverage"
report_lines << ""
report_lines << "- External cases: #{coverage.fetch("total_external_cases")}"
report_lines << "- Mapped cases: #{coverage.fetch("mapped_cases")}"
report_lines << "- Domain exits: #{coverage.fetch("domain_exit_cases")}"
report_lines << "- Unmapped cases: #{coverage.fetch("unmapped_cases")}"
report_lines << "- Unique stages: #{coverage.fetch("unique_stages").join(", ")}"
report_lines << "- Unique macro stages: #{coverage.fetch("unique_macro_stages").join(", ")}"
report_lines << "- Primary skills touched: #{coverage.fetch("unique_primary_skills").join(", ")}"
report_lines << "- Roles touched: #{coverage.fetch("roles_touched").join(", ")}"
report_lines << ""
report_lines << "## Routed Cases"
report_lines << ""
routed_cases.each do |entry|
  report_lines << "### #{entry.fetch("source_file")} / Scenario #{entry.fetch("source_scenario")} - #{entry.fetch("title")}"
  report_lines << ""
  report_lines << "- Stage: `#{entry.fetch("routed_stage_id")}`"
  report_lines << "- Skill: `#{entry["primary_skill"]}` / fallback `#{entry["fallback_skill"]}`"
  report_lines << "- Roles: #{entry.fetch("required_roles").empty? ? "none" : entry.fetch("required_roles").join(", ")}"
  report_lines << "- Artifacts: #{entry.fetch("required_artifacts").join(", ")}"
  report_lines << "- Gate: #{entry["stage_gate"]}"
  report_lines << "- Status: `#{entry.fetch("route_status")}`"
  report_lines << ""
end

File.write(File.join(output_dir, "external-benchmark-report.md"), report_lines.join("\n"))

puts "run-external-benchmark: #{summary.fetch("status")}"
puts "source_cases: #{coverage.fetch("total_external_cases")}"
puts "mapped_cases: #{coverage.fetch("mapped_cases")}"
puts "output_dir: #{output_dir}"
exit(summary.fetch("status") == "PASS" ? 0 : 2)
