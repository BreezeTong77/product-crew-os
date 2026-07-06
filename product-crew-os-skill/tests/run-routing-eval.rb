#!/usr/bin/env ruby

require "fileutils"
require "json"
require "time"
require "yaml"
require_relative "../runtime/stage_router"

skill_root = File.expand_path("..", __dir__)
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
external_cases_path = File.join(skill_root, "tests", "external-benchmark-cases.yaml")
results_dir = File.join(skill_root, "tests", "results")
output_dir = ARGV[0] || File.join(results_dir, "routing-eval-#{Time.now.strftime("%Y%m%d-%H%M%S")}")
latest_report = File.join(results_dir, "routing-eval-latest.md")
latest_json = File.join(results_dir, "routing-eval-latest.json")

def as_set(value)
  Array(value).compact.map(&:to_s).reject(&:empty?).uniq
end

def ratio(numerator, denominator)
  return 1.0 if denominator.zero?

  numerator.to_f / denominator
end

def compare_case(router, item)
  expected_domain = item.fetch("expected_domain_intent")
  expected_stage = item["expected_stage_id"]
  expected_skill = item["expected_primary_skill"]
  expected_roles = as_set(item["expected_roles"])
  route = router.route(item.fetch("prompt"))
  actual_domain = route.fetch("domain_intent")
  actual_stage = route["stage_id"]
  actual_skill = route["primary_skill"]
  actual_roles = as_set(route.fetch("required_roles") + route.fetch("triggered_roles"))
  role_intersection = expected_roles & actual_roles
  role_precision = ratio(role_intersection.length, actual_roles.length)
  role_recall = ratio(role_intersection.length, expected_roles.length)
  {
    "case_id" => item.fetch("case_id"),
    "source" => item.fetch("source"),
    "prompt" => item.fetch("prompt"),
    "expected_domain_intent" => expected_domain,
    "actual_domain_intent" => actual_domain,
    "expected_stage_id" => expected_stage,
    "actual_stage_id" => actual_stage,
    "expected_primary_skill" => expected_skill,
    "actual_primary_skill" => actual_skill,
    "expected_roles" => expected_roles,
    "actual_roles" => actual_roles,
    "domain_hit" => expected_domain == actual_domain,
    "stage_hit" => expected_stage == actual_stage,
    "skill_hit" => expected_skill == actual_skill,
    "agent_precision" => role_precision.round(3),
    "agent_recall" => role_recall.round(3),
    "route_status" => route.fetch("route_status"),
    "confidence" => route.fetch("confidence"),
    "matched_signals" => route.fetch("matched_signals")
  }
end

prompt_eval = YAML.load_file(prompt_eval_path)
internal_cases = prompt_eval.fetch("cases").map do |entry|
  expected = entry.fetch("expected")
  {
    "case_id" => entry.fetch("case_id"),
    "source" => "internal_44_sop",
    "prompt" => entry.fetch("user_input"),
    "expected_domain_intent" => "product_work",
    "expected_stage_id" => entry.fetch("stage_id"),
    "expected_primary_skill" => expected["primary_skill"],
    "expected_roles" => as_set(expected["required_roles"] + expected["triggered_roles"])
  }
end

external_cases = YAML.load_file(external_cases_path).fetch("cases").map do |entry|
  entry.merge("source" => "external_gold")
end

router = SemanticStageRouter.new(prompt_eval_path: prompt_eval_path)
rows = (internal_cases + external_cases).map { |item| compare_case(router, item) }
product_rows = rows.select { |row| row.fetch("expected_domain_intent") == "product_work" }
external_rows = rows.select { |row| row.fetch("source") == "external_gold" }
domain_exit_rows = rows.select { |row| row.fetch("expected_domain_intent") == "non_product_task" }

metrics = {
  "total_cases" => rows.length,
  "internal_cases" => internal_cases.length,
  "external_cases" => external_cases.length,
  "domain_accuracy" => ratio(rows.count { |row| row["domain_hit"] }, rows.length).round(3),
  "stage_accuracy" => ratio(product_rows.count { |row| row["stage_hit"] }, product_rows.length).round(3),
  "skill_hit_rate" => ratio(product_rows.count { |row| row["skill_hit"] }, product_rows.length).round(3),
  "agent_precision" => ratio(product_rows.sum { |row| row["agent_precision"] }, product_rows.length).round(3),
  "agent_recall" => ratio(product_rows.sum { |row| row["agent_recall"] }, product_rows.length).round(3),
  "external_stage_accuracy" => ratio(external_rows.select { |row| row.fetch("expected_domain_intent") == "product_work" }.count { |row| row["stage_hit"] }, external_rows.count { |row| row.fetch("expected_domain_intent") == "product_work" }).round(3),
  "domain_exit_accuracy" => ratio(domain_exit_rows.count { |row| row["domain_hit"] && row["actual_stage_id"].nil? }, domain_exit_rows.length).round(3)
}

thresholds = {
  "domain_accuracy" => 0.95,
  "stage_accuracy" => 0.85,
  "skill_hit_rate" => 0.85,
  "agent_recall" => 0.80,
  "domain_exit_accuracy" => 1.0
}
failed_thresholds = thresholds.select { |key, threshold| metrics.fetch(key) < threshold }
status = failed_thresholds.empty? ? "PASS" : "FAIL"

FileUtils.mkdir_p(output_dir)
FileUtils.mkdir_p(results_dir)
payload = {
  "status" => status,
  "generated_at" => Time.now.utc.iso8601,
  "metrics" => metrics,
  "thresholds" => thresholds,
  "failed_thresholds" => failed_thresholds,
  "cases" => rows
}
File.write(File.join(output_dir, "routing-eval-results.json"), JSON.pretty_generate(payload))
File.write(latest_json, JSON.pretty_generate(payload))

lines = [
  "# Semantic Router Eval Report",
  "",
  "- Status: `#{status}`",
  "- Total cases: `#{metrics["total_cases"]}`",
  "- Internal 44 SOP cases: `#{metrics["internal_cases"]}`",
  "- External gold cases: `#{metrics["external_cases"]}`",
  "- Domain accuracy: `#{metrics["domain_accuracy"]}`",
  "- Stage accuracy: `#{metrics["stage_accuracy"]}`",
  "- Skill hit rate: `#{metrics["skill_hit_rate"]}`",
  "- Agent precision: `#{metrics["agent_precision"]}`",
  "- Agent recall: `#{metrics["agent_recall"]}`",
  "- External stage accuracy: `#{metrics["external_stage_accuracy"]}`",
  "- Domain exit accuracy: `#{metrics["domain_exit_accuracy"]}`",
  "",
  "## Failed Thresholds",
  ""
]
if failed_thresholds.empty?
  lines << "- None"
else
  failed_thresholds.each { |key, threshold| lines << "- `#{key}` expected >= #{threshold}, got #{metrics.fetch(key)}" }
end

lines += ["", "## Misses", ""]
misses = rows.reject { |row| row["domain_hit"] && (row["expected_domain_intent"] == "non_product_task" || row["stage_hit"] && row["skill_hit"] && row["agent_recall"] >= 0.8) }
if misses.empty?
  lines << "- None"
else
  misses.each do |row|
    lines << "### #{row["case_id"]}"
    lines << ""
    lines << "- Source: `#{row["source"]}`"
    lines << "- Expected: domain=`#{row["expected_domain_intent"]}` stage=`#{row["expected_stage_id"]}` skill=`#{row["expected_primary_skill"]}` roles=#{row["expected_roles"].join(", ")}"
    lines << "- Actual: domain=`#{row["actual_domain_intent"]}` stage=`#{row["actual_stage_id"]}` skill=`#{row["actual_primary_skill"]}` roles=#{row["actual_roles"].join(", ")}"
    lines << "- Agent recall: `#{row["agent_recall"]}`"
    lines << ""
  end
end

File.write(File.join(output_dir, "routing-eval-report.md"), lines.join("\n"))
File.write(latest_report, lines.join("\n"))

puts "run-routing-eval: #{status}"
metrics.each { |key, value| puts "#{key}: #{value}" }
puts "report: #{latest_report}"
exit(status == "PASS" ? 0 : 2)
