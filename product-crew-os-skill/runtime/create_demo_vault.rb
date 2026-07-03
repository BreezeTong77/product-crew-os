#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "time"
require "yaml"

skill_root = File.expand_path("..", __dir__)
runtime = File.join(skill_root, "runtime", "pco_runtime.rb")
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
bundled_index_path = File.join(skill_root, "references", "bundled-skill-index.md")

def parse_options(argv)
  options = {
    "output_dir" => File.expand_path("runtime-demo-vault", Dir.pwd),
    "project_id" => "runtime-demo-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}",
    "project_name" => "Product Crew OS Runtime Demo",
    "owner" => "demo-user",
    "limit" => "44"
  }
  until argv.empty?
    key = argv.shift
    raise "expected --key, got #{key}" unless key&.start_with?("--")
    value = argv.shift
    raise "missing value for #{key}" if value.nil?
    options[key.sub(/\A--/, "").tr("-", "_")] = value
  end
  options
end

def run_cmd(*args)
  stdout, stderr, status = Open3.capture3(*args)
  raise "command failed: #{args.join(" ")}\n#{stderr}\n#{stdout}" unless status.success?
  stdout
end

def split_skill_candidates(value)
  value.to_s.split(/\s*\/\s*/).map(&:strip).reject(&:empty?)
end

def choose_skill(primary, fallback, bundled)
  primary_hit = split_skill_candidates(primary).find { |skill| bundled.key?(skill) }
  return [primary_hit, "completed"] if primary_hit

  fallback_hit = split_skill_candidates(fallback).find { |skill| bundled.key?(skill) }
  return [fallback_hit, "fallback_used"] if fallback_hit

  ["artifact-template", "template_used"]
end

options = parse_options(ARGV)
output_dir = File.expand_path(options.fetch("output_dir"))
workspace = File.join(output_dir, "workspace")
db = File.join(workspace, "product-crew-os.sqlite3")
obsidian_dir = File.join(output_dir, "obsidian-vault")
project_id = options.fetch("project_id")
project_name = options.fetch("project_name")
limit = options.fetch("limit").to_i

FileUtils.mkdir_p(output_dir)
source_artifact_dir = File.join(output_dir, "source-artifacts")
FileUtils.mkdir_p(source_artifact_dir)

cases = YAML.load_file(prompt_eval_path).fetch("cases").first(limit)
bundled_index = File.read(bundled_index_path)
bundled = bundled_index.scan(/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`/).to_h

run_cmd(
  "ruby", runtime, "init-project",
  "--workspace", workspace,
  "--db", db,
  "--project-id", project_id,
  "--name", project_name,
  "--description", "Persistent runtime demo generated from Product Crew OS SOP cases.",
  "--owner", options.fetch("owner")
)

cases.each do |test_case|
  expected = test_case.fetch("expected")
  stage_id = test_case.fetch("stage_id")
  macro_stage = test_case.fetch("macro_stage")
  chosen_skill, status = choose_skill(expected.fetch("primary_skill"), expected.fetch("fallback_skill"), bundled)
  artifact_name = Array(expected.fetch("required_artifacts")).first || "#{stage_id}.md"
  roles = (Array(expected["required_roles"]) + Array(expected["triggered_roles"])).uniq
  roles = ["Coach"] if roles.empty?
  content_path = File.join(source_artifact_dir, "#{stage_id}.md")
  File.write(content_path, <<~MARKDOWN)
    ## 持久化 Runtime Demo Artifact

    - Case: `#{test_case.fetch("case_id")}`
    - Stage: `#{stage_id}`
    - Macro stage: `#{macro_stage}`
    - 实际调用 skill: `#{chosen_skill}`
    - Skill 状态: `#{status}`
    - Stage Gate: #{expected.fetch("stage_gate")}

    用户输入：

    > #{test_case.fetch("user_input")}

    本文件由 `runtime/create_demo_vault.rb` 生成，用于验证 Product Crew OS 的项目记忆、Artifact 版本、团队评审记录、Context Packet、事件指标和 Obsidian 导出链路。
  MARKDOWN

  run_cmd(
    "ruby", runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", stage_id,
    "--macro-stage", macro_stage,
    "--sop-id", stage_id,
    "--user-input", test_case.fetch("user_input"),
    "--route-confidence", "demo",
    "--primary-skill", chosen_skill,
    "--fallback-skill", expected.fetch("fallback_skill"),
    "--skill-status", status,
    "--artifact-name", artifact_name,
    "--artifact-content-file", content_path,
    "--artifact-status", "draft",
    "--gate-status", "conditional_pass",
    "--gate-result", expected.fetch("stage_gate"),
    "--review-roles", roles.join(","),
    "--source-ref", "persistent-demo:#{test_case.fetch("case_id")}"
  )
end

run_cmd(
  "ruby", runtime, "export-obsidian",
  "--workspace", workspace,
  "--db", db,
  "--project-id", project_id,
  "--output-dir", obsidian_dir
)

summary_sql = <<~SQL
  SELECT
    (SELECT COUNT(*) FROM sop_runs WHERE project_id='#{project_id}') AS sop_runs,
    (SELECT COUNT(*) FROM skill_runs WHERE project_id='#{project_id}') AS skill_runs,
    (SELECT COUNT(*) FROM artifacts WHERE project_id='#{project_id}') AS artifacts,
    (SELECT COUNT(*) FROM agent_invocations WHERE project_id='#{project_id}') AS agent_invocations,
    (SELECT COUNT(*) FROM events WHERE project_id='#{project_id}') AS events;
SQL
summary = JSON.parse(run_cmd("sqlite3", "-json", db, summary_sql)).first

puts JSON.pretty_generate(
  project_id: project_id,
  project_name: project_name,
  output_dir: output_dir,
  workspace: workspace,
  database: db,
  obsidian_vault: obsidian_dir,
  counts: summary
)
