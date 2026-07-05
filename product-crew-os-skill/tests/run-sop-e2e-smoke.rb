#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

skill_root = File.expand_path("..", __dir__)
runtime = File.join(skill_root, "runtime", "pco_runtime.rb")
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
bundled_index_path = File.join(skill_root, "references", "bundled-skill-index.md")

def run_cmd(*args)
  stdout, stderr, status = Open3.capture3(*args)
  raise "command failed: #{args.join(" ")}\n#{stderr}\n#{stdout}" unless status.success?
  stdout
end

def query_count(db, table)
  stdout = run_cmd("sqlite3", "-json", db, "SELECT COUNT(*) AS count FROM #{table};")
  JSON.parse(stdout).first.fetch("count")
end

def query_value(db, sql, key)
  stdout = run_cmd("sqlite3", "-json", db, sql)
  rows = stdout.strip.empty? ? [] : JSON.parse(stdout)
  rows.first&.fetch(key, nil)
end

def event_count(db, event_type)
  query_value(db, "SELECT COUNT(*) AS count FROM events WHERE event_type = '#{event_type}';", "count")
end

def split_skill_candidates(value)
  value.to_s.split(/\s*\/\s*/).map(&:strip).reject(&:empty?)
end

def choose_skill(primary, fallback, bundled)
  primary_candidates = split_skill_candidates(primary)
  fallback_candidates = split_skill_candidates(fallback)
  primary_hit = primary_candidates.find { |skill| bundled.key?(skill) }
  return [primary_hit, "completed"] if primary_hit

  fallback_hit = fallback_candidates.find { |skill| bundled.key?(skill) }
  return [fallback_hit, "fallback_used"] if fallback_hit

  ["artifact-template", "template_used"]
end

prompt_eval = YAML.load_file(prompt_eval_path)
cases = prompt_eval.fetch("cases")
bundled_index = File.read(bundled_index_path)
bundled = bundled_index.scan(/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`/).to_h

raise "expected 44 SOP cases, got #{cases.length}" unless cases.length == 44

Dir.mktmpdir("pco-sop-e2e-") do |dir|
  db = File.join(dir, "product-crew-os.sqlite3")
  workspace = File.join(dir, "workspace")
  project_id = "sop-e2e"

  run_cmd(
    "ruby", runtime, "init-project",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--name", "SOP E2E Smoke",
    "--description", "44 SOP runtime adapter smoke",
    "--owner", "runtime"
  )

  fallback_used = 0
  template_used = 0

  cases.each do |test_case|
    expected = test_case.fetch("expected")
    stage_id = test_case.fetch("stage_id")
    macro_stage = test_case.fetch("macro_stage")
    primary = expected.fetch("primary_skill")
    fallback = expected.fetch("fallback_skill")
    chosen_skill, status = choose_skill(primary, fallback, bundled)
    fallback_used += 1 if status == "fallback_used"
    template_used += 1 if status == "template_used"

    skill_note =
      if bundled.key?(chosen_skill)
        skill_path = File.join(skill_root, bundled.fetch(chosen_skill), "SKILL.md")
        skill_body = File.read(skill_path)
        raise "empty skill file: #{skill_path}" if skill_body.strip.empty?
        "读取内置 skill: `#{chosen_skill}` from `#{bundled.fetch(chosen_skill)}`"
      else
        "使用 artifact 模板兜底: `#{chosen_skill}`"
      end

    artifact_name = Array(expected.fetch("required_artifacts")).first || "#{stage_id}.md"
    roles = (Array(expected["required_roles"]) + Array(expected["triggered_roles"])).uniq
    roles = ["Coach"] if roles.empty?
    content_path = File.join(dir, "#{stage_id}.md")
    File.write(content_path, <<~MARKDOWN)
      ## SOP E2E Smoke Artifact

      - Case: `#{test_case.fetch("case_id")}`
      - Stage: `#{stage_id}`
      - Macro stage: `#{macro_stage}`
      - Router primary: `#{primary}`
      - Router fallback: `#{fallback}`
      - Actual skill: `#{chosen_skill}`
      - Skill status: `#{status}`
      - Stage gate: #{expected.fetch("stage_gate")}
      - Skill read proof: #{skill_note}

      用户输入：

      > #{test_case.fetch("user_input")}
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
      "--route-confidence", "e2e_smoke",
      "--primary-skill", chosen_skill,
      "--fallback-skill", fallback,
      "--skill-status", status,
      "--artifact-name", artifact_name,
      "--artifact-content-file", content_path,
      "--artifact-status", "draft",
      "--gate-status", "conditional_pass",
      "--gate-result", expected.fetch("stage_gate"),
      "--review-roles", roles.join(","),
      "--source-ref", "prompt-eval:#{test_case.fetch("case_id")}"
    )
  end

  obsidian_dir = File.join(dir, "obsidian")
  run_cmd(
    "ruby", runtime, "export-obsidian",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--output-dir", obsidian_dir
  )

	  expected_counts = {
	    "projects" => 1,
	    "stages" => 44,
	    "sop_runs" => 44,
	    "skill_runs" => 44,
	    "artifacts" => 44,
	    "artifact_versions" => 44,
	    "review_sessions" => 44
	  }
  expected_counts.each do |table, expected_count|
    actual_count = query_count(db, table)
    raise "#{table} expected #{expected_count}, got #{actual_count}" unless actual_count == expected_count
  end

	  %w[context_packets agent_invocations raw_review_records review_items fts_documents events].each do |table|
	    actual_count = query_count(db, table)
	    raise "#{table} expected at least 44, got #{actual_count}" if actual_count < 44
	  end

  {
    "stage_detected" => 44,
    "skill_selected" => 44,
	    "stage_gate_decision" => 44,
	    "agent_summoned" => 44,
	    "memory_snapshot_built" => 44,
	    "review_session_opened" => 44,
	    "raw_review_record_written" => 44
	  }.each do |event_type, minimum_count|
    actual_count = event_count(db, event_type)
    raise "#{event_type} expected at least #{minimum_count}, got #{actual_count}" if actual_count < minimum_count
  end

  unique_stages = query_value(db, "SELECT COUNT(DISTINCT stage_id) AS count FROM sop_runs;", "count")
  raise "expected 44 unique stages in sop_runs, got #{unique_stages}" unless unique_stages == 44

  fallback_count = query_value(db, "SELECT COUNT(*) AS count FROM skill_runs WHERE status = 'fallback_used';", "count")
  template_count = query_value(db, "SELECT COUNT(*) AS count FROM skill_runs WHERE status = 'template_used';", "count")
  raise "expected fallback_used count #{fallback_used}, got #{fallback_count}" unless fallback_count == fallback_used
  raise "expected template_used count #{template_used}, got #{template_count}" unless template_count == template_used

  exported_artifacts = Dir[File.join(obsidian_dir, "Projects", "sop-e2e-smoke", "**", "*.md")]
  raise "expected exported Obsidian markdown files, got 0" if exported_artifacts.empty?

	  flow_dirs = Dir[File.join(obsidian_dir, "Projects", "sop-e2e-smoke", "[0-9][0-9]_*")].select { |path| File.directory?(path) }
	  non_empty_flow_dirs = flow_dirs.select { |path| Dir[File.join(path, "*.md")].any? }
	  raise "expected artifacts across 10 product flow directories, got #{non_empty_flow_dirs.length}" unless non_empty_flow_dirs.length == 10
	  raise "expected exported review sessions" unless Dir[File.join(obsidian_dir, "Projects", "sop-e2e-smoke", "_项目账本", "review-sessions", "*.md")].any?
	  raise "expected exported raw review records" unless Dir[File.join(obsidian_dir, "Projects", "sop-e2e-smoke", "_项目账本", "raw-review-records", "**", "*.md")].any?
	end

puts "run-sop-e2e-smoke: PASS"
