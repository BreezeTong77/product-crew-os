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

def run_cmd_env(errors, env, *args)
  stdout, stderr, status = Open3.capture3(env, *args)
  unless status.success?
    errors << "command failed: #{args.join(" ")}\n#{stderr}\n#{stdout}"
    return {}
  end
  JSON.parse(stdout)
rescue JSON::ParserError => e
  errors << "invalid JSON from #{args.join(" ")}: #{e.message}\n#{stdout}"
  {}
end

def db_rows(errors, db, sql)
  stdout, stderr, status = Open3.capture3("sqlite3", "-json", db, sql)
  unless status.success?
    errors << "sqlite query failed: #{stderr}"
    return []
  end
  stdout.strip.empty? ? [] : JSON.parse(stdout)
rescue JSON::ParserError => e
  errors << "invalid sqlite JSON: #{e.message}"
  []
end

Dir.mktmpdir("pco-runtime-smoke") do |dir|
  db = File.join(dir, "pco.sqlite3")
  workspace = File.join(dir, "workspace")
  vault = File.join(dir, "obsidian-vault")
  project_id = "runtime-smoke"
  ruby = RbConfig.ruby

  legacy_db = File.join(dir, "legacy.sqlite3")
  legacy_schema = <<~SQL
    CREATE TABLE projects (
      project_id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT DEFAULT '',
      owner TEXT DEFAULT '',
      current_stage_id TEXT DEFAULT 'project_intake',
      current_macro_stage TEXT DEFAULT 'opportunity_discovery',
      status TEXT DEFAULT 'active',
      workspace_path TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE stages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project_id TEXT NOT NULL,
      stage_id TEXT NOT NULL,
      macro_stage TEXT DEFAULT '',
      status TEXT DEFAULT 'in_progress',
      gate_status TEXT DEFAULT 'not_ready',
      started_at TEXT NOT NULL,
      completed_at TEXT DEFAULT ''
    );
  SQL
  _stdout, legacy_stderr, legacy_status = Open3.capture3("sqlite3", legacy_db, stdin_data: legacy_schema)
  assert(errors, legacy_status.success?, "could not create legacy runtime fixture: #{legacy_stderr}")
  legacy_init = run_cmd(errors, ruby, runtime, "init-project", "--workspace", File.join(dir, "legacy-workspace"), "--db", legacy_db, "--project-id", "legacy", "--name", "Legacy Migration", "--owner", "qa")
  legacy_columns = db_rows(errors, legacy_db, "PRAGMA table_info(stages);").map { |column| column.fetch("name") }
  legacy_indexes = db_rows(errors, legacy_db, "PRAGMA index_list(stages);").map { |index| index.fetch("name") }
  assert(errors, legacy_init["project_id"] == "legacy", "legacy database could not initialize after migration")
  assert(errors, %w[stage_run_id requested_gate_status route_decision_id artifact_id skill_run_id].all? { |column| legacy_columns.include?(column) }, "legacy database did not receive stage lifecycle columns")
  assert(errors, legacy_indexes.include?("idx_stages_stage_run_id"), "legacy database did not create stage_run_id index after migration")

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
    "--gate-status", "blocked",
    "--review-mode", "simulated_placeholder",
    "--gate-result", "Structured review artifacts were persisted."
  )
  assert(errors, turn["review_session_id"].to_s != "", "record-turn did not return review_session_id")
  assert(errors, turn["route_decision_id"].to_s.start_with?("route_"), "record-turn did not return route_decision_id")
  assert(errors, turn["gate_status"] == "blocked_runtime_preflight", "simulated or unexecuted Skill turn should not pass a stage gate")
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

  blocked_embedding_turn = run_cmd_env(
    errors,
    { "PCO_REQUIRE_REAL_EMBEDDING" => "1" },
    ruby,
    runtime,
    "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--macro-stage", "requirement_analysis",
    "--sop-id", "mvp_scope",
    "--user-input", "我来定：第一阶段就做审核工作台 AI 辅助判定 + 知识库 RAG 联动。",
    "--primary-skill", "scope-cutting",
    "--fallback-skill", "shape-up",
    "--artifact-name", "Embedding Required Smoke",
    "--artifact-content", "This artifact should not pass without real embedding.",
    "--gate-status", "conditional_pass",
    "--gate-result", "This should be blocked by missing real embedding."
  )
  embedding_issues = blocked_embedding_turn.dig("runtime_preflight", "issues") || []
  assert(errors, blocked_embedding_turn["gate_status"] == "blocked_runtime_preflight", "runtime did not block when real embedding was required")
  assert(errors, embedding_issues.include?("real_embedding_missing"), "runtime preflight did not report real_embedding_missing")

  blocked_subagent_turn = run_cmd_env(
    errors,
    { "PCO_REQUIRE_REAL_SUBAGENTS" => "1" },
    ruby,
    runtime,
    "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "formal_requirements_review",
    "--macro-stage", "cross_functional_review",
    "--sop-id", "formal_requirements_review",
    "--user-input", "正式需求评审，验证必需角色不能用模拟冒充。",
    "--primary-skill", "stakeholder-alignment-checker",
    "--fallback-skill", "prd-critic",
    "--artifact-name", "Subagent Required Smoke",
    "--artifact-content", "This artifact should not pass without real sub-agent invocation.",
    "--review-roles", "Tech",
    "--gate-status", "conditional_pass",
    "--review-mode", "none",
    "--gate-result", "This should be blocked by missing real sub-agent."
  )
  subagent_issues = blocked_subagent_turn.dig("runtime_preflight", "issues") || []
  assert(errors, blocked_subagent_turn["gate_status"] == "blocked_runtime_preflight", "runtime did not block when real sub-agents were required")
  assert(errors, subagent_issues.any? { |issue| issue.include?("real_subagent_invocation_missing") }, "runtime preflight did not report real_subagent_invocation_missing")

  valid_skill_contract = {
    "contract_ref" => "smoke:valid-external-workflow",
    "skill_id" => "scope-cutting",
    "execution_mode" => "external_workflow",
    "allowed_stage_ids" => ["mvp_scope"],
    "capability_scope" => ["范围裁剪", "取舍分析"],
    "approved_actions" => ["read_artifacts", "draft_artifact"],
    "observed_actions" => ["read_artifacts", "draft_artifact"],
    "control_boundary" => {
      "may_change_stage" => false,
      "may_decide_gate" => false,
      "may_write_project_memory" => false,
      "may_call_agents" => false
    },
    "output_evidence" => {
      "artifact_name" => "Valid External Skill Output",
      "source_ref" => "skill:scope-cutting:runtime-smoke"
    }
  }
  host_execution = run_cmd(
    errors,
    ruby, runtime, "record-host-skill-execution",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--skill-id", "scope-cutting",
    "--runtime-model-id", "coze-model-smoke",
    "--host-run-id", "host-run-smoke-001",
    "--raw-output", "范围裁剪的真实宿主模型原始输出。",
    "--observed-actions-json", "[\"read_artifacts\",\"draft_artifact\"]",
    "--source-ref", "host:coze-smoke"
  )
  assert(errors, host_execution["execution_id"].to_s.start_with?("skill_exec_"), "runtime did not record host skill execution evidence")
  valid_skill_turn = run_cmd(
    errors,
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--sop-id", "mvp_scope",
    "--user-input", "先做 MVP，帮我砍范围",
    "--primary-skill", "scope-cutting",
    "--artifact-name", "Valid External Skill Output",
    "--artifact-content", "Skill may use its own scope-cutting method before returning this artifact.",
    "--skill-contract-json", JSON.generate(valid_skill_contract),
    "--skill-execution-id", host_execution["execution_id"].to_s,
    "--gate-status", "conditional_pass",
    "--review-mode", "standard_sop"
  )
  assert(errors, valid_skill_turn["gate_status"] == "awaiting_external_review", "valid external skill contract should wait for routed reviewer callbacks")
  assert(errors, valid_skill_turn.dig("skill_execution", "contract_status") == "validated", "valid external skill contract was not validated")
  valid_stage = db_rows(errors, db, "SELECT status, gate_status, completed_at FROM stages WHERE stage_run_id='#{valid_skill_turn.fetch("stage_run_id")}';").first || {}
  assert(errors, valid_stage["status"] == "review_pending", "review-pending stage should not be marked completed")
  assert(errors, valid_stage["completed_at"].to_s.empty?, "review-pending stage should not have completed_at")

  no_execution_turn = run_cmd(
    errors,
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--sop-id", "mvp_scope",
    "--user-input", "先做 MVP，帮我砍范围",
    "--primary-skill", "scope-cutting",
    "--artifact-name", "No Execution Receipt",
    "--artifact-content", "Only a draft without any Skill receipt.",
    "--gate-status", "conditional_pass",
    "--review-mode", "none"
  )
  no_execution_issues = no_execution_turn.dig("runtime_preflight", "issues") || []
  assert(errors, no_execution_turn["gate_status"] == "blocked_runtime_preflight", "missing Skill receipt and required reviews must not pass")
  assert(errors, no_execution_issues.any? { |issue| issue.include?("skill_execution_contract_missing") }, "missing Skill receipt was not reported")
  assert(errors, no_execution_issues.include?("review_mode_none_with_required_roles"), "required reviewers could still be bypassed with review_mode=none")

  wrong_skill_execution = run_cmd(
    errors,
    ruby, runtime, "record-host-skill-execution",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--skill-id", "deliver-prd",
    "--runtime-model-id", "coze-model-smoke",
    "--host-run-id", "host-run-smoke-wrong-skill",
    "--raw-output", "A real host ran the wrong Skill for this SOP.",
    "--observed-actions-json", "[\"read_artifacts\",\"draft_artifact\"]",
    "--source-ref", "host:coze-smoke:wrong-skill"
  )
  wrong_skill_contract = valid_skill_contract.merge(
    "contract_ref" => "smoke:wrong-skill",
    "skill_id" => "deliver-prd",
    "output_evidence" => { "artifact_name" => "Wrong Skill Output", "source_ref" => "skill:deliver-prd:runtime-smoke" }
  )
  wrong_skill_turn = run_cmd(
    errors,
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--sop-id", "mvp_scope",
    "--user-input", "先做 MVP，帮我砍范围",
    "--primary-skill", "deliver-prd",
    "--artifact-name", "Wrong Skill Output",
    "--artifact-content", "The wrong but real Skill output must not pass.",
    "--skill-contract-json", JSON.generate(wrong_skill_contract),
    "--skill-execution-id", wrong_skill_execution.fetch("execution_id"),
    "--gate-status", "conditional_pass",
    "--review-mode", "none"
  )
  assert(errors, wrong_skill_turn["gate_status"] == "blocked_runtime_preflight", "a routed SOP must reject a real but wrong Skill")
  assert(errors, (wrong_skill_turn.dig("runtime_preflight", "issues") || []).any? { |issue| issue.start_with?("skill_route_mismatch") }, "wrong Skill was not tied back to the routed Skill")

  missing_evidence_turn = run_cmd(
    errors,
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--sop-id", "mvp_scope",
    "--user-input", "先做 MVP，帮我砍范围",
    "--primary-skill", "scope-cutting",
    "--artifact-name", "Missing Host Evidence",
    "--artifact-content", "No host execution evidence was returned.",
    "--skill-contract-json", JSON.generate(valid_skill_contract.merge("output_evidence" => { "artifact_name" => "Missing Host Evidence", "source_ref" => "skill:scope-cutting:missing" })),
    "--gate-status", "conditional_pass",
    "--review-mode", "none"
  )
  assert(errors, missing_evidence_turn["gate_status"] == "blocked_runtime_preflight", "external workflow without host execution evidence should be blocked")

  invalid_skill_contract = Marshal.load(Marshal.dump(valid_skill_contract))
  invalid_skill_contract["contract_ref"] = "smoke:overreach"
  invalid_skill_contract["approved_actions"] << "decide_gate"
  invalid_skill_contract["observed_actions"] << "decide_gate"
  invalid_skill_contract["control_boundary"]["may_decide_gate"] = true
  invalid_skill_contract["output_evidence"]["artifact_name"] = "Overreach Skill Output"
  invalid_skill_turn = run_cmd(
    errors,
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "mvp_scope",
    "--sop-id", "mvp_scope",
    "--user-input", "先做 MVP，帮我砍范围",
    "--primary-skill", "scope-cutting",
    "--artifact-name", "Overreach Skill Output",
    "--artifact-content", "The draft is retained, but the skill attempted to decide the gate.",
    "--skill-contract-json", JSON.generate(invalid_skill_contract),
    "--gate-status", "conditional_pass",
    "--review-mode", "none"
  )
  assert(errors, invalid_skill_turn["gate_status"] == "blocked_runtime_preflight", "overreaching external skill should not pass the stage gate")
  assert(errors, invalid_skill_turn.dig("skill_execution", "overreach_detected") == true, "external skill overreach was not recorded")

  export = run_cmd(errors, ruby, runtime, "export-obsidian", "--workspace", workspace, "--db", db, "--project-id", project_id, "--output-dir", vault)
  project_path = export["project_path"].to_s
  assert(errors, File.exist?(File.join(project_path, "00_项目首页.md")), "obsidian export missing project home")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "decision-log.md")), "obsidian export missing decision log")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "review-items.yaml")), "obsidian export missing review items")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "routing", "stage-route-decision.jsonl")), "obsidian export missing route trace records")
  assert(errors, Dir[File.join(project_path, "_项目账本", "review-sessions", "*.md")].any?, "obsidian export missing review session records")
  assert(errors, Dir[File.join(project_path, "_项目账本", "raw-review-records", "**", "*.md")].any?, "obsidian export missing raw review records")
  assert(errors, Dir[File.join(project_path, "_项目账本", "skill-executions", "*.md")].any?, "obsidian export missing host skill execution evidence")
  assert(errors, File.exist?(File.join(project_path, "_团队记忆", "tech.md")), "obsidian export missing role memory")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "导出清单.md")), "obsidian export missing export manifest")
  flow_dirs = Dir[File.join(project_path, "[0-9][0-9]_*")].select { |path| File.directory?(path) }
  assert(errors, flow_dirs.all? { |path| Dir[File.join(path, "*.md")].any? }, "obsidian export created an empty product flow directory")

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
