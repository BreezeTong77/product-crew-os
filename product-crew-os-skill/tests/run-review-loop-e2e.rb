#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require "yaml"

skill_root = File.expand_path("..", __dir__)
runtime = File.join(skill_root, "runtime", "pco_runtime.rb")
ruby = RbConfig.ruby
results_dir = File.join(skill_root, "tests", "results")
latest_report = File.join(results_dir, "review-loop-e2e-latest.md")
latest_json = File.join(results_dir, "review-loop-e2e-latest.json")

def run_cmd(*args)
  stdout, stderr, status = Open3.capture3(*args)
  raise "command failed: #{args.join(" ")}\n#{stderr}\n#{stdout}" unless status.success?
  stdout
end

def run_json(*args)
  JSON.parse(run_cmd(*args))
end

def query_json(db, sql)
  stdout = run_cmd("sqlite3", "-json", db, sql)
  stdout.strip.empty? ? [] : JSON.parse(stdout)
end

def assert(errors, condition, message)
  errors << message unless condition
end

errors = []
checks = []
payload = {}

Dir.mktmpdir("pco-review-loop-e2e-") do |dir|
  db = File.join(dir, "product-crew-os.sqlite3")
  workspace = File.join(dir, "workspace")
  vault = File.join(dir, "obsidian")
  project_id = "review-loop-e2e"

  run_json(ruby, runtime, "init-project", "--workspace", workspace, "--db", db, "--project-id", project_id, "--name", "Review Loop E2E", "--description", "Structured review loop validation", "--owner", "tests")

  route = run_json(ruby, runtime, "route-intent", "--workspace", workspace, "--db", db, "--project-id", project_id, "--user-input", "我想画个原型图，类似小红书首页的信息流。")
  assert(errors, route["stage_id"] == "low_fi_prototype", "route-intent did not classify low-fi prototype")
  checks << "route-intent classified prototype request"

  turn = run_json(
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "formal_requirements_review",
    "--macro-stage", "cross_functional_review",
    "--sop-id", "formal_requirements_review",
    "--user-input", "正式需求评审，验证结构化 Review Loop。",
    "--route-confidence", "e2e",
    "--primary-skill", "stakeholder-alignment-checker",
    "--fallback-skill", "prd-critic",
    "--artifact-name", "Review Loop Artifact",
    "--artifact-content", "评审对象：信息流首页原型和需求边界。",
    "--review-roles", "Tech,QA",
    "--gate-status", "blocked",
    "--gate-result", "等待用户决策后再关闭"
  )
  session_id = turn.fetch("review_session_id")
  artifact_id = turn.fetch("artifact_id")
  assert(errors, !session_id.empty?, "record-turn did not create review session")
  session_status = query_json(db, "SELECT status FROM review_sessions WHERE session_id='#{session_id}';").first&.fetch("status")
  assert(errors, session_status == "awaiting_user_decision", "review session should wait for user decision, got #{session_status}")
  checks << "record-turn opened review session and moved to awaiting_user_decision"

  qa_role = turn.fetch("roles").find { |role| role["role_key"] == "QA" }
  tech_role = turn.fetch("roles").find { |role| role["role_key"] == "Tech" }
  assert(errors, qa_role && tech_role, "record-turn did not create Tech and QA role outputs")
  invocations = query_json(db, "SELECT role_key, role_title, display_name, stage_id, artifact_id, trigger_reason, runtime_nickname FROM agent_invocations ORDER BY created_at ASC;")
  assert(errors, invocations.any? { |row| row["role_key"] == "QA" && row["display_name"] == "李测" && row["role_title"].to_s != "" }, "QA invocation did not bind configured display name 李测")
  assert(errors, invocations.all? { |row| row["stage_id"].to_s != "" && row["artifact_id"].to_s != "" && row["trigger_reason"].to_s != "" }, "invocation ledger missing stage/artifact/trigger reason")
  checks << "configured role names and invocation ledger fields persisted"

  packet = run_json(ruby, runtime, "build-context-packet", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "QA", "--stage-id", "formal_requirements_review", "--artifact-id", artifact_id, "--review-question", "验证 QA 真实原文透传")
  real_invocation = run_json(
    ruby, runtime, "record-invocation",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--role-key", "QA",
    "--stage-id", "formal_requirements_review",
    "--artifact-id", artifact_id,
    "--trigger-reason", "e2e real subagent handoff",
    "--runtime-agent-id", "agent-runtime-e2e-qa",
    "--runtime-nickname", "Averroes",
    "--context-packet-id", packet.fetch("packet_id"),
    "--real", "true",
    "--result", "block"
  )
  unique_raw = "QA_REAL_RAW_REVIEW_E2E_#{Time.now.to_i}: 李测认为验收状态缺少异常分支，必须补充。"
  raw_record = run_json(
    ruby, runtime, "write-raw-review-record",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--session-id", session_id,
    "--role-key", "QA",
    "--artifact-id", artifact_id,
    "--context-packet-id", packet.fetch("packet_id"),
    "--invocation-id", real_invocation.fetch("invocation_id"),
    "--conclusion", "block",
    "--raw-review", unique_raw
  )
  raw_text = File.read(raw_record.fetch("path"))
  assert(errors, raw_text.include?(unique_raw), "raw review file did not preserve exact real sub-agent text")
  assert(errors, raw_text.include?("Display name: `李测`"), "raw review did not keep configured display name")
  assert(errors, raw_text.include?("Runtime nickname: `Averroes` (audit only)"), "raw review did not keep runtime nickname as audit-only")
  checks << "real raw review text persisted with configured identity and audit nickname"

  must_fix = run_json(
    ruby, runtime, "write-review-item",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--session-id", session_id,
    "--artifact-id", artifact_id,
    "--stage-id", "formal_requirements_review",
    "--role-key", "QA",
    "--artifact-ref", "Review Loop Artifact#异常分支",
    "--conclusion", "block",
    "--priority", "must_fix",
    "--comment", "验收状态缺少异常分支。",
    "--recommendation", "补充异常状态和回滚验证。",
    "--status", "open"
  )

  unconfirmed_close = run_json(ruby, runtime, "record-review-decision", "--workspace", workspace, "--db", db, "--project-id", project_id, "--session-id", session_id, "--action", "close", "--user-confirmed", "false", "--notes", "主控不能替用户关闭")
  assert(errors, unconfirmed_close["result"] == "needs_user_confirmation", "unconfirmed close should require user confirmation")
  assert(errors, unconfirmed_close["status"] == "awaiting_user_decision", "unconfirmed close should not change review session status")

  blocked_close = run_json(ruby, runtime, "record-review-decision", "--workspace", workspace, "--db", db, "--project-id", project_id, "--session-id", session_id, "--action", "close", "--user-confirmed", "true", "--notes", "仍有 must-fix")
  assert(errors, blocked_close["result"] == "blocked_by_open_must_fix", "confirmed close should block when must-fix remains open")
  assert(errors, blocked_close["status"] == "awaiting_user_decision", "blocked close should keep session awaiting user decision")

  accepted = run_json(ruby, runtime, "record-review-decision", "--workspace", workspace, "--db", db, "--project-id", project_id, "--session-id", session_id, "--action", "accept", "--item-ids", must_fix.fetch("review_item_id"), "--user-confirmed", "true", "--notes", "用户采纳 QA must-fix")
  assert(errors, accepted["result"] == "revision_needed", "accepting must-fix should move session to revision_needed")

  closed = run_json(ruby, runtime, "record-review-decision", "--workspace", workspace, "--db", db, "--project-id", project_id, "--session-id", session_id, "--action", "close", "--user-confirmed", "true", "--notes", "用户确认关闭评审")
  assert(errors, closed["result"] == "closed_by_user", "review session should close only after user confirmed and blockers resolved")
  assert(errors, closed["status"] == "closed_by_user", "review session status should be closed_by_user")
  checks << "review decision loop requires user confirmation and blocks unresolved must-fix"

  memory = run_json(ruby, runtime, "write-agent-memory", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "QA", "--summary", "李测总会优先检查异常分支和验收状态。", "--source-ref", "review-loop-e2e", "--confidence", "confirmed")
  memory_packet = run_json(ruby, runtime, "build-context-packet", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "QA", "--stage-id", "formal_requirements_review", "--artifact-id", artifact_id, "--review-question", "验证记忆反哺")
  packet_yaml = YAML.load_file(memory_packet.fetch("path"))
  recent_memory = packet_yaml.dig("memory_snapshot", "project_role_memory", "recent") || []
  assert(errors, memory["memory_id"].to_s != "", "write-agent-memory did not return memory_id")
  assert(errors, recent_memory.any? { |row| row["summary"].to_s.include?("异常分支") }, "context packet did not inject QA role memory")
  checks << "role memory writes to team member and injects into next context packet"

  timeout_turn = run_json(
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "formal_requirements_review",
    "--macro-stage", "cross_functional_review",
    "--sop-id", "formal_requirements_review",
    "--user-input", "验证必需角色超时阻塞。",
    "--route-confidence", "e2e",
    "--primary-skill", "stakeholder-alignment-checker",
    "--fallback-skill", "prd-critic",
    "--artifact-name", "Timeout Artifact",
    "--artifact-content", "评审对象：技术负责人必须返回后才能过阶段门。",
    "--review-roles", "Tech",
    "--gate-status", "blocked",
    "--gate-result", "等待技术负责人返回"
  )
  timeout_session_id = timeout_turn.fetch("review_session_id")
  timeout_artifact_id = timeout_turn.fetch("artifact_id")
  timeout_packet = run_json(ruby, runtime, "build-context-packet", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--stage-id", "formal_requirements_review", "--artifact-id", timeout_artifact_id, "--review-question", "验证超时状态")
  timeout_invocation = run_json(
    ruby, runtime, "record-invocation",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--role-key", "Tech",
    "--session-id", timeout_session_id,
    "--stage-id", "formal_requirements_review",
    "--artifact-id", timeout_artifact_id,
    "--trigger-reason", "required role timeout e2e",
    "--runtime-agent-id", "agent-runtime-e2e-tech",
    "--runtime-nickname", "Euler",
    "--context-packet-id", timeout_packet.fetch("packet_id"),
    "--real", "true",
    "--invocation-status", "timeout",
    "--timeout-seconds", "120",
    "--required-for-gate", "true",
    "--result", "timeout"
  )
  timeout_status = query_json(db, "SELECT status FROM review_sessions WHERE session_id='#{timeout_session_id}';").first&.fetch("status")
  timeout_event = query_json(db, "SELECT COUNT(*) AS count FROM events WHERE project_id='#{project_id}' AND event_type='agent_invocation_timeout';").first&.fetch("count").to_i
  assert(errors, timeout_invocation["invocation_status"] == "timeout", "timeout invocation did not return timeout status")
  assert(errors, timeout_status == "blocked_by_timeout", "required role timeout should block review session, got #{timeout_status}")
  assert(errors, timeout_event.positive?, "timeout event was not written")
  checks << "required role timeout writes invocation ledger and blocks review session"

  export = run_json(ruby, runtime, "export-obsidian", "--workspace", workspace, "--db", db, "--project-id", project_id, "--output-dir", vault)
  project_path = export.fetch("project_path")
  assert(errors, File.exist?(File.join(project_path, "_团队记忆", "qa.md")), "Obsidian export missing QA team memory")
  assert(errors, Dir[File.join(project_path, "_项目账本", "raw-review-records", "**", "*.md")].any?, "Obsidian export missing raw review records")
  checks << "project asset export includes team memory and raw review records"

  payload = {
    "status" => errors.empty? ? "PASS" : "FAIL",
    "generated_at" => Time.now.utc.iso8601,
    "runtime_db" => db,
    "workspace" => workspace,
    "review_session_id" => session_id,
    "artifact_id" => artifact_id,
    "checks" => checks,
    "errors" => errors
  }
end

FileUtils.mkdir_p(results_dir)
File.write(latest_json, JSON.pretty_generate(payload))
report_lines = [
  "# Review Loop E2E Report",
  "",
  "- Status: `#{payload.fetch("status")}`",
  "- Review session: `#{payload["review_session_id"]}`",
  "- Artifact: `#{payload["artifact_id"]}`",
  "",
  "## Checks",
  ""
]
payload.fetch("checks").each { |check| report_lines << "- #{check}" }
report_lines << ""
report_lines << "## Errors"
report_lines << ""
if payload.fetch("errors").empty?
  report_lines << "- None"
else
  payload.fetch("errors").each { |error| report_lines << "- #{error}" }
end
File.write(latest_report, report_lines.join("\n"))

puts "run-review-loop-e2e: #{payload.fetch("status")}"
puts "checks: #{payload.fetch("checks").length}"
puts "report: #{latest_report}"
exit(payload.fetch("status") == "PASS" ? 0 : 1)
