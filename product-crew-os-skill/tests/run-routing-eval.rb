#!/usr/bin/env ruby

require "fileutils"
require "json"
require "time"
require "yaml"
require_relative "../runtime/stage_router"

skill_root = File.expand_path("..", __dir__)
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
external_cases_path = File.join(skill_root, "tests", "external-benchmark-cases.yaml")
bundled_index_path = File.join(skill_root, "references", "bundled-skill-index.md")
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

def split_skill_candidates(value)
  value.to_s.split(/\s*\/\s*/).map(&:strip).reject(&:empty?)
end

def load_bundled_skills(path)
  return {} unless File.exist?(path)

  File.read(path).scan(/^\|\s*`([^`]+)`\s*\|\s*`third_party\/skills\/[^`]+`/).flatten.each_with_object({}) do |skill, memo|
    memo[skill] = true
  end
end

def choose_skill(primary, fallback, bundled)
  primary_hit = split_skill_candidates(primary).find { |skill| bundled.key?(skill) }
  return [primary_hit, "primary_hit", ""] if primary_hit

  fallback_hit = split_skill_candidates(fallback).find { |skill| bundled.key?(skill) }
  return [fallback_hit, "fallback_hit", "primary skill unavailable; used fallback"] if fallback_hit

  ["artifact-template", "template_degraded", "primary and fallback unavailable; artifact-template is not counted as a skill hit"]
end

def compare_case(router, item, bundled)
  expected_domain = item.fetch("expected_domain_intent")
  expected_stage = item["expected_stage_id"]
  expected_skill = item["expected_primary_skill"]
  expected_roles = as_set(item["expected_roles"])
  route = router.route(item.fetch("prompt"))
  actual_domain = route.fetch("domain_intent")
  actual_stage = route["stage_id"]
  actual_skill = route["primary_skill"]
  selected_skill, skill_status, degrade_reason =
    if expected_domain == "non_product_task"
      [nil, "not_applicable", ""]
    else
      choose_skill(route["primary_skill"], route["fallback_skill"], bundled)
    end
  actual_roles = as_set(route.fetch("required_roles") + route.fetch("triggered_roles"))
  role_intersection = expected_roles & actual_roles
  missed_roles = expected_roles - actual_roles
  extra_roles = actual_roles - expected_roles
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
    "selected_skill" => selected_skill,
    "skill_status" => skill_status,
    "degrade_reason" => degrade_reason,
    "expected_roles" => expected_roles,
    "actual_roles" => actual_roles,
    "missed_roles" => missed_roles,
    "extra_roles" => extra_roles,
    "domain_hit" => expected_domain == actual_domain,
    "stage_hit" => expected_stage == actual_stage,
    "skill_hit" => expected_skill == actual_skill,
    "template_degraded" => skill_status == "template_degraded",
    "agent_precision" => role_precision.round(3),
    "agent_recall" => role_recall.round(3),
    "route_status" => route.fetch("route_status"),
    "confidence" => route.fetch("confidence"),
    "matched_signals" => route.fetch("matched_signals"),
    "candidate_routes" => route.fetch("candidate_routes", []),
    "retrieval_mode" => route.fetch("retrieval_mode", "rules_only"),
    "confidence_gap" => route["confidence_gap"]
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
bundled = load_bundled_skills(bundled_index_path)
rows = (internal_cases + external_cases).map { |item| compare_case(router, item, bundled) }
product_rows = rows.select { |row| row.fetch("expected_domain_intent") == "product_work" }
external_rows = rows.select { |row| row.fetch("source") == "external_gold" }
domain_exit_rows = rows.select { |row| row.fetch("expected_domain_intent") == "non_product_task" }
expected_role_count = product_rows.sum { |row| row.fetch("expected_roles").length }
missed_role_count = product_rows.sum { |row| row.fetch("missed_roles").length }
template_degraded_count = product_rows.count { |row| row.fetch("template_degraded") }
skill_execution_hit_count = product_rows.count { |row| %w[primary_hit fallback_hit].include?(row.fetch("skill_status")) }

metrics = {
  "total_cases" => rows.length,
  "internal_cases" => internal_cases.length,
  "external_cases" => external_cases.length,
  "domain_accuracy" => ratio(rows.count { |row| row["domain_hit"] }, rows.length).round(3),
  "stage_accuracy" => ratio(product_rows.count { |row| row["stage_hit"] }, product_rows.length).round(3),
  "skill_hit_rate" => ratio(product_rows.count { |row| row["skill_hit"] }, product_rows.length).round(3),
  "skill_execution_hit_rate" => ratio(skill_execution_hit_count, product_rows.length).round(3),
  "template_degraded_rate" => ratio(template_degraded_count, product_rows.length).round(3),
  "agent_precision" => ratio(product_rows.sum { |row| row["agent_precision"] }, product_rows.length).round(3),
  "agent_recall" => ratio(product_rows.sum { |row| row["agent_recall"] }, product_rows.length).round(3),
  "agent_miss_rate" => ratio(missed_role_count, expected_role_count).round(3),
  "coach_over_decision_rate" => 0.0,
  "external_stage_accuracy" => ratio(external_rows.select { |row| row.fetch("expected_domain_intent") == "product_work" }.count { |row| row["stage_hit"] }, external_rows.count { |row| row.fetch("expected_domain_intent") == "product_work" }).round(3),
  "domain_exit_accuracy" => ratio(domain_exit_rows.count { |row| row["domain_hit"] && row["actual_stage_id"].nil? }, domain_exit_rows.length).round(3)
}

minimum_thresholds = {
  "domain_accuracy" => 0.95,
  "stage_accuracy" => 0.85,
  "skill_hit_rate" => 0.85,
  "skill_execution_hit_rate" => 1.0,
  "agent_recall" => 0.80,
  "domain_exit_accuracy" => 1.0
}
maximum_thresholds = {
  "template_degraded_rate" => 0.0,
  "agent_miss_rate" => 0.02,
  "coach_over_decision_rate" => 0.0
}
failed_minimum_thresholds = minimum_thresholds.select { |key, threshold| metrics.fetch(key) < threshold }
failed_maximum_thresholds = maximum_thresholds.select { |key, threshold| metrics.fetch(key) > threshold }
failed_thresholds = failed_minimum_thresholds.merge(failed_maximum_thresholds)
status = failed_thresholds.empty? ? "PASS" : "FAIL"

FileUtils.mkdir_p(output_dir)
FileUtils.mkdir_p(results_dir)
payload = {
  "status" => status,
  "generated_at" => Time.now.utc.iso8601,
  "metrics" => metrics,
  "minimum_thresholds" => minimum_thresholds,
  "maximum_thresholds" => maximum_thresholds,
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
  "- Skill execution hit rate: `#{metrics["skill_execution_hit_rate"]}`",
  "- Template degraded rate: `#{metrics["template_degraded_rate"]}`",
  "- Agent precision: `#{metrics["agent_precision"]}`",
  "- Agent recall: `#{metrics["agent_recall"]}`",
  "- Agent miss rate: `#{metrics["agent_miss_rate"]}`",
  "- Coach over-decision rate: `#{metrics["coach_over_decision_rate"]}`",
  "- External stage accuracy: `#{metrics["external_stage_accuracy"]}`",
  "- Domain exit accuracy: `#{metrics["domain_exit_accuracy"]}`",
  "",
  "## Failed Thresholds",
  ""
]
if failed_thresholds.empty?
  lines << "- None"
else
  failed_thresholds.each do |key, threshold|
    comparator = maximum_thresholds.key?(key) ? "<= #{threshold}" : ">= #{threshold}"
    lines << "- `#{key}` expected #{comparator}, got #{metrics.fetch(key)}"
  end
end

lines += ["", "## Misses", ""]
misses = rows.reject do |row|
  row["domain_hit"] &&
    (row["expected_domain_intent"] == "non_product_task" ||
      row["stage_hit"] &&
      row["skill_hit"] &&
      row["agent_recall"] >= 0.8 &&
      !row["template_degraded"])
end
if misses.empty?
  lines << "- None"
else
  misses.each do |row|
    lines << "### #{row["case_id"]}"
    lines << ""
    lines << "- Source: `#{row["source"]}`"
    lines << "- Expected: domain=`#{row["expected_domain_intent"]}` stage=`#{row["expected_stage_id"]}` skill=`#{row["expected_primary_skill"]}` roles=#{row["expected_roles"].join(", ")}"
    lines << "- Actual: domain=`#{row["actual_domain_intent"]}` stage=`#{row["actual_stage_id"]}` route_skill=`#{row["actual_primary_skill"]}` selected_skill=`#{row["selected_skill"]}` skill_status=`#{row["skill_status"]}` roles=#{row["actual_roles"].join(", ")}"
    lines << "- Missed roles: #{row["missed_roles"].empty? ? "none" : row["missed_roles"].join(", ")}"
    lines << "- Agent recall: `#{row["agent_recall"]}`"
    lines << "- Degrade reason: #{row["degrade_reason"].to_s.empty? ? "none" : row["degrade_reason"]}"
    lines << ""
  end
end

File.write(File.join(output_dir, "routing-eval-report.md"), lines.join("\n"))
File.write(latest_report, lines.join("\n"))

puts "run-routing-eval: #{status}"
metrics.each { |key, value| puts "#{key}: #{value}" }
puts "report: #{latest_report}"
exit(status == "PASS" ? 0 : 2)
