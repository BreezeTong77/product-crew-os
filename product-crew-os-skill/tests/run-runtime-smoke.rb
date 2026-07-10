#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

skill_root = File.expand_path("..", __dir__)
runtime = File.join(skill_root, "runtime", "pco_runtime.rb")
errors = []

def assert(errors, condition, message)
  errors << message unless condition
end

def run_cmd(errors, *args)
  stdout, stderr, status = Open3.capture3(*args)
  unless status.success?
    errors << "command failed: #{args.join(" ")}\n#{stderr}\n#{stdout}"
    return {}
  end
  JSON.parse(stdout)
rescue JSON::ParserError => e
  errors << "invalid JSON from #{args.join(" ")}: #{e.message}\n#{stdout}"
  {}
end

Dir.mktmpdir("pco-runtime-smoke") do |dir|
  db = File.join(dir, "pco.sqlite3")
  workspace = File.join(dir, "workspace")
  vault = File.join(dir, "obsidian-vault")
  project_id = "runtime-smoke"
  ruby = RbConfig.ruby

  init = run_cmd(errors, ruby, runtime, "init-project", "--workspace", workspace, "--db", db, "--project-id", project_id, "--name", "Runtime Smoke", "--owner", "qa")
  assert(errors, File.exist?(db), "runtime did not create sqlite database")
  assert(errors, File.directory?(init["workspace"].to_s), "runtime did not create project workspace")

  artifact = run_cmd(errors, ruby, runtime, "save-artifact", "--workspace", workspace, "--db", db, "--project-id", project_id, "--name", "MVP Scope", "--stage-id", "requirement_analysis", "--sop-id", "sop_16_mvp_scope", "--content", "Runtime smoke validates artifact persistence.", "--source-ref", "smoke:user")
  assert(errors, File.exist?(artifact["path"].to_s), "runtime did not write artifact file")

  parallel = [
    [ruby, runtime, "write-decision", "--workspace", workspace, "--db", db, "--project-id", project_id, "--title", "Runtime MVP", "--decision", "Ship SQLite runtime first.", "--stage-id", "requirement_analysis", "--rationale", "Memory must be executable, not only described.", "--source-ref", "smoke:decision"],
    [ruby, runtime, "write-review-item", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--reviewer-name", "张工", "--comment", "Check write failure visibility.", "--recommendation", "Exit non-zero and keep event trail.", "--stage-id", "requirement_analysis", "--source-ref", "smoke:review"],
    [ruby, runtime, "write-agent-memory", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--summary", "Tech watches database writes, rollback, and error visibility.", "--source-ref", "smoke:review", "--confidence", "confirmed"]
  ]

  parallel.map do |cmd|
    Thread.new { run_cmd(errors, *cmd) }
  end.each(&:join)

	  packet = run_cmd(errors, ruby, runtime, "build-context-packet", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--stage-id", "requirement_analysis", "--review-question", "Check runtime MVP risk")
	  assert(errors, File.exist?(packet["path"].to_s), "runtime did not write context packet")

	  invocation = run_cmd(
	    errors,
	    ruby,
	    runtime,
	    "record-invocation",
	    "--workspace", workspace,
	    "--db", db,
	    "--project-id", project_id,
	    "--role-key", "Tech",
	    "--runtime-agent-id", "agent-runtime-001",
	    "--runtime-nickname", "Faraday",
	    "--context-packet-id", packet["packet_id"].to_s,
	    "--real", "true",
	    "--result", "block"
	  )
	  assert(errors, invocation["display_name"] == "张工", "real invocation did not resolve Tech display_name from crew-personas")
	  assert(errors, invocation["role_title"] == "技术负责人", "real invocation did not resolve Tech role_title from crew-personas")
	  assert(errors, invocation["runtime_nickname"] == "Faraday", "real invocation did not preserve runtime_nickname as audit metadata")

  turn = run_cmd(
    errors,
    ruby,
    runtime,
    "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "formal_requirements_review",
    "--macro-stage", "cross_functional_review",
    "--sop-id", "formal_requirements_review",
    "--user-input", "正式需求评审，验证结构化 Review Loop。",
    "--primary-skill", "stakeholder-alignment-checker",
    "--fallback-skill", "prd-critic",
    "--artifact-name", "Structured Review Smoke",
    "--artifact-content", "Runtime smoke validates review session and raw review record persistence.",
    "--review-roles", "Biz,Tech,Design",
    "--gate-status", "conditional_pass",
    "--gate-result", "Structured review artifacts were persisted."
  )
  assert(errors, turn["review_session_id"].to_s != "", "record-turn did not return review_session_id")
  assert(errors, turn["route_decision_id"].to_s.start_with?("route_"), "record-turn did not return route_decision_id")
  assert(errors, turn["runtime_preflight"].is_a?(Hash) && turn["runtime_preflight"]["status"] == "passed", "record-turn did not pass runtime preflight")
  route_trace_path = File.join(workspace, "memory", "projects", project_id, "routing", "stage-route-decision.jsonl")
  assert(errors, File.exist?(route_trace_path), "runtime did not write routing/stage-route-decision.jsonl")
  assert(errors, File.read(route_trace_path).include?(turn["route_decision_id"].to_s), "route trace file does not contain record-turn route_decision_id")

  blocked_turn = run_cmd(
    errors,
    ruby,
    runtime,
    "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--macro-stage", "requirement_analysis",
    "--sop-id", "mvp_scope",
    "--user-input", "今天上海天气怎么样？",
    "--primary-skill", "scope-cutting",
    "--fallback-skill", "shape-up",
    "--artifact-name", "Blocked Runtime Preflight Smoke",
    "--artifact-content", "This artifact should not pass a product stage gate.",
    "--gate-status", "conditional_pass",
    "--gate-result", "This should be blocked by runtime preflight."
  )
  assert(errors, blocked_turn["gate_status"] == "blocked_runtime_preflight", "runtime did not downgrade conditional_pass when route preflight failed")

  export = run_cmd(errors, ruby, runtime, "export-obsidian", "--workspace", workspace, "--db", db, "--project-id", project_id, "--output-dir", vault)
  project_path = export["project_path"].to_s
  assert(errors, File.exist?(File.join(project_path, "00_项目首页.md")), "obsidian export missing project home")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "decision-log.md")), "obsidian export missing decision log")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "review-items.yaml")), "obsidian export missing review items")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "routing", "stage-route-decision.jsonl")), "obsidian export missing route trace records")
  assert(errors, Dir[File.join(project_path, "_项目账本", "review-sessions", "*.md")].any?, "obsidian export missing review session records")
  assert(errors, Dir[File.join(project_path, "_项目账本", "raw-review-records", "**", "*.md")].any?, "obsidian export missing raw review records")
  assert(errors, File.exist?(File.join(project_path, "_团队记忆", "tech.md")), "obsidian export missing role memory")

	  query = "select 'projects' as table_name, count(*) as count from projects union all select 'artifacts', count(*) from artifacts union all select 'decisions', count(*) from decisions union all select 'review_sessions', count(*) from review_sessions union all select 'raw_review_records', count(*) from raw_review_records union all select 'review_items', count(*) from review_items union all select 'agent_memories', count(*) from agent_memories union all select 'context_packets', count(*) from context_packets;"
	  stdout, stderr, status = Open3.capture3("sqlite3", "-json", db, query)
	  if status.success?
	    counts = JSON.parse(stdout).each_with_object({}) { |row, memo| memo[row.fetch("table_name")] = row.fetch("count").to_i }
	    %w[projects artifacts decisions review_sessions raw_review_records review_items agent_memories context_packets].each do |table|
	      assert(errors, counts[table].to_i >= 1, "runtime sqlite table #{table} is empty")
	    end
  else
    errors << "sqlite count query failed: #{stderr}"
  end

	  stdout, stderr, status = Open3.capture3("sqlite3", "-json", db, "SELECT role_key, role_title, display_name, runtime_agent_id, runtime_nickname FROM agent_invocations;")
	  if status.success?
	    invocations = JSON.parse(stdout)
	    assert(errors, invocations.any? { |row| row["role_key"] == "Tech" && row["display_name"] == "张工" && row["runtime_nickname"] == "Faraday" }, "invocation ledger did not keep runtime nickname separate from configured role")
	    assert(errors, invocations.none? { |row| %w[Biz Tech Design].include?(row["role_key"]) && row["display_name"] == row["role_key"] }, "known crew role used role_key as user-facing display_name")
	  else
	    errors << "sqlite invocation query failed: #{stderr}"
	  end
end

if errors.empty?
  puts "run-runtime-smoke: PASS"
else
  warn "run-runtime-smoke: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
