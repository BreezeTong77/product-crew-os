#!/usr/bin/env ruby

require "fileutils"
require "digest"
require "json"
require "open3"
require "rbconfig"
require "securerandom"
require "time"
require "tmpdir"
require "yaml"

RUNNER_VERSION = "loop-50-ledger-v2"

skill_root = File.expand_path("..", __dir__)
runtime = File.join(skill_root, "runtime", "pco_runtime.rb")
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
bundled_index_path = File.join(skill_root, "references", "bundled-skill-index.md")
results_dir = File.join(skill_root, "tests", "results")
ledger_schema_path = File.join(skill_root, "tests", "test-ledger-schema.sql")
original_argv = ARGV.dup
release_gate = ARGV.delete("--release-gate")
force = ARGV.delete("--force")
force = true if release_gate
no_ledger = ARGV.delete("--no-ledger")
ledger_db_index = ARGV.index("--ledger-db")
ledger_db = if ledger_db_index
  value = ARGV[ledger_db_index + 1]
  raise "--ledger-db requires a path" if value.to_s.strip.empty?

  ARGV.slice!(ledger_db_index, 2)
  value
else
  File.join(results_dir, "product-crew-os-test-ledger.sqlite3")
end
raise "unknown arguments: #{ARGV.join(" ")}" unless ARGV.empty?
report_path = File.join(results_dir, force ? "loop-50-cases-latest-force.md" : "loop-50-cases-latest.md")
ruby = RbConfig.ruby

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

def query_value(db, sql, key = "count")
  query_json(db, sql).first&.fetch(key, nil)
end

def sqlite_version
  run_cmd("sqlite3", "--version").split.first
end

def git_sha
  stdout, _stderr, status = Open3.capture3("git", "rev-parse", "--short", "HEAD")
  status.success? ? stdout.strip : "unknown"
end

def file_digest(path)
  File.exist?(path) ? Digest::SHA256.file(path).hexdigest : "missing"
end

def case_hash(case_id:, payload:, files:)
  file_state = files.sort.map do |path|
    [path.sub(%r{\A.*/product-crew-os-skill/}, "product-crew-os-skill/"), file_digest(path)]
  end
  Digest::SHA256.hexdigest(JSON.generate({
    runner_version: RUNNER_VERSION,
    case_id: case_id,
    payload: payload,
    files: file_state
  }))
end

def now_iso
  Time.now.utc.iso8601
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

def markdown_table(rows)
  lines = [
    "| # | Case | 类型 | 结果 | Bad Case / 验证点 | 证据 |",
    "| --- | --- | --- | --- | --- | --- |"
  ]
  rows.each_with_index do |row, index|
    lines << "| #{index + 1} | `#{row.fetch(:case_id)}` | #{row.fetch(:case_type)} | #{row.fetch(:status)} | #{row.fetch(:badcase)} | #{row.fetch(:evidence)} |"
  end
  lines.join("\n")
end

def record_result(results:, ledger:, suite_run_id:, case_id:, case_type:, status:, badcase:, evidence:, case_hash:, source_ref:)
  results << {
    case_id: case_id,
    case_type: case_type,
    status: status,
    badcase: badcase,
    evidence: evidence
  }
  ledger.record_case(
    suite_run_id: suite_run_id,
    case_id: case_id,
    suite: "loop-50-cases",
    case_type: case_type,
    title: badcase,
    source_ref: source_ref,
    case_hash: case_hash,
    status: status,
    evidence: evidence,
    badcase: badcase
  )
end

def skip_result(results:, ledger:, suite_run_id:, case_id:, case_type:, badcase:, case_hash:, source_ref:)
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: case_type,
    status: "SKIP_PASS",
    badcase: badcase,
    evidence: "`test-ledger`",
    case_hash: case_hash,
    source_ref: source_ref
  )
end

class TestLedger
  attr_reader :db

  def initialize(db:, schema_path:, disabled:)
    @db = db
    @disabled = disabled
    return if @disabled

    FileUtils.mkdir_p(File.dirname(@db))
    sqlite(File.read(schema_path))
    ensure_column("test_cases", "last_checked_at", "TEXT DEFAULT ''")
    ensure_column("test_case_runs", "suite_run_id", "TEXT DEFAULT ''")
  end

  def disabled?
    @disabled
  end

  def passed?(case_id, hash)
    return false if disabled?

    rows = query("SELECT last_status, last_case_hash FROM test_cases WHERE case_id = #{q(case_id)} LIMIT 1;")
    rows.first && rows.first["last_status"] == "PASS" && rows.first["last_case_hash"] == hash
  end

  def start_suite_run(suite:, runner_version:, git_sha:, command:, force_rerun:, release_gate:, ruby_version:, sqlite_version:)
    return "disabled" if disabled?

    at = now_iso
    suite_run_id = "suite_#{at}_#{SecureRandom.hex(4)}"
    sqlite(<<~SQL)
      INSERT INTO suite_runs
        (suite_run_id, suite, runner_version, git_sha, command, force_rerun, release_gate, ruby_version, sqlite_version, status, started_at)
      VALUES
        (#{q(suite_run_id)}, #{q(suite)}, #{q(runner_version)}, #{q(git_sha)}, #{q(command)}, #{force_rerun ? 1 : 0}, #{release_gate ? 1 : 0}, #{q(ruby_version)}, #{q(sqlite_version)}, 'running', #{q(at)});
    SQL
    suite_run_id
  end

  def finish_suite_run(suite_run_id:, status:, total_count:, pass_count:, fail_count:, skip_count:, actual_executed_count:, report_path:)
    return if disabled?

    sqlite(<<~SQL)
      UPDATE suite_runs
      SET
        status = #{q(status)},
        total_count = #{total_count.to_i},
        pass_count = #{pass_count.to_i},
        fail_count = #{fail_count.to_i},
        skip_count = #{skip_count.to_i},
        actual_executed_count = #{actual_executed_count.to_i},
        report_path = #{q(report_path)},
        finished_at = #{q(now_iso)}
      WHERE suite_run_id = #{q(suite_run_id)};
    SQL
  end

  def record_case(suite_run_id:, case_id:, suite:, case_type:, title:, source_ref:, case_hash:, status:, evidence:, badcase:)
    return if disabled?

    at = now_iso
    if status == "SKIP_PASS"
      sqlite(<<~SQL)
        UPDATE test_cases
        SET
          updated_at = #{q(at)},
          last_checked_at = #{q(at)},
          skip_count = skip_count + 1
        WHERE case_id = #{q(case_id)};
      SQL
    else
    sqlite(<<~SQL)
      INSERT INTO test_cases
        (case_id, suite, case_type, title, source_ref, created_at, updated_at, last_status, last_case_hash, last_evidence, last_run_at, last_checked_at, pass_count, fail_count, skip_count)
      VALUES
        (#{q(case_id)}, #{q(suite)}, #{q(case_type)}, #{q(title)}, #{q(source_ref)}, #{q(at)}, #{q(at)}, #{q(status)}, #{q(case_hash)}, #{q(evidence)}, #{q(at)}, #{q(at)}, #{status == "PASS" ? 1 : 0}, #{status == "FAIL" ? 1 : 0}, 0)
      ON CONFLICT(case_id) DO UPDATE SET
        suite = excluded.suite,
        case_type = excluded.case_type,
        title = excluded.title,
        source_ref = excluded.source_ref,
        updated_at = excluded.updated_at,
        last_status = excluded.last_status,
        last_case_hash = excluded.last_case_hash,
        last_evidence = excluded.last_evidence,
        last_run_at = excluded.last_run_at,
        last_checked_at = excluded.last_checked_at,
        pass_count = test_cases.pass_count + CASE WHEN excluded.last_status = 'PASS' THEN 1 ELSE 0 END,
        fail_count = test_cases.fail_count + CASE WHEN excluded.last_status = 'FAIL' THEN 1 ELSE 0 END;
    SQL
    end
    sqlite(<<~SQL)
      INSERT INTO test_case_runs
        (run_id, suite_run_id, case_id, suite, case_type, case_hash, status, evidence, badcase, source_ref, started_at, finished_at)
      VALUES
        (#{q("run_#{at}_#{SecureRandom.hex(4)}_#{case_id}")}, #{q(suite_run_id)}, #{q(case_id)}, #{q(suite)}, #{q(case_type)}, #{q(case_hash)}, #{q(status)}, #{q(evidence)}, #{q(badcase)}, #{q(source_ref)}, #{q(at)}, #{q(at)});
    SQL
  end

  def seed_badcase(badcase_id:, case_id:, title:, symptom:, fix_summary:, regression_file:, status:, severity: "P1", source_ref: "loop-50")
    return if disabled?

    at = now_iso
    sqlite(<<~SQL)
      INSERT INTO badcases
        (badcase_id, case_id, title, symptom, fix_summary, regression_file, status, severity, source_ref, created_at, updated_at)
      VALUES
        (#{q(badcase_id)}, #{q(case_id)}, #{q(title)}, #{q(symptom)}, #{q(fix_summary)}, #{q(regression_file)}, #{q(status)}, #{q(severity)}, #{q(source_ref)}, #{q(at)}, #{q(at)})
      ON CONFLICT(badcase_id) DO UPDATE SET
        case_id = excluded.case_id,
        title = excluded.title,
        symptom = excluded.symptom,
        fix_summary = excluded.fix_summary,
        regression_file = excluded.regression_file,
        status = excluded.status,
        severity = excluded.severity,
        source_ref = excluded.source_ref,
        updated_at = excluded.updated_at;
    SQL
  end

  private

  def ensure_column(table, column, definition)
    columns = query("PRAGMA table_info(#{table});").map { |row| row.fetch("name") }
    return if columns.include?(column)

    sqlite("ALTER TABLE #{table} ADD COLUMN #{column} #{definition};")
  end

  def sqlite(sql)
    stdout, stderr, status = Open3.capture3("sqlite3", "-cmd", "PRAGMA foreign_keys = ON;", @db, sql)
    raise "ledger sqlite failed: #{stderr}\n#{stdout}" unless status.success?

    stdout
  end

  def query(sql)
    stdout, stderr, status = Open3.capture3("sqlite3", "-cmd", "PRAGMA foreign_keys = ON;", "-json", @db, sql)
    raise "ledger query failed: #{stderr}\n#{stdout}" unless status.success?

    stdout.strip.empty? ? [] : JSON.parse(stdout)
  end

  def q(value)
    "'#{value.to_s.gsub("'", "''")}'"
  end
end

prompt_eval = YAML.load_file(prompt_eval_path)
base_cases = prompt_eval.fetch("cases")
raise "expected 44 base SOP cases, got #{base_cases.length}" unless base_cases.length == 44

bundled_index = File.read(bundled_index_path)
bundled = bundled_index.scan(/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`/).to_h
signature_files = [
  __FILE__,
  ledger_schema_path,
  runtime,
  File.join(skill_root, "runtime", "db", "schema.sql"),
  prompt_eval_path,
  bundled_index_path,
  File.join(skill_root, "..", "README.md"),
  File.join(skill_root, "references", "structured-review-loop.md"),
  File.join(skill_root, "references", "experience", "agent-customization-and-team-style.md"),
  File.join(skill_root, "references", "subagent-memory-runtime-contract.md"),
  File.join(skill_root, "config", "crew-personas.yaml")
]
ledger = TestLedger.new(db: ledger_db, schema_path: ledger_schema_path, disabled: no_ledger)
suite_run_id = ledger.start_suite_run(
  suite: "loop-50-cases",
  runner_version: RUNNER_VERSION,
  git_sha: git_sha,
  command: "ruby product-crew-os-skill/tests/run-loop-50-cases.rb #{original_argv.join(" ")}".strip,
  force_rerun: force,
  release_gate: release_gate,
  ruby_version: RUBY_VERSION,
  sqlite_version: sqlite_version
)

[
  ["L45", "L45_non_product_task_exit", "非产品问题被强行套入 SOP", "用户问普通问题时系统仍进入 Product Crew OS 阶段流", "README / SOP 明确 Domain Gate，非产品任务退出 Product Crew OS", "run-loop-50-cases.rb"],
  ["L46", "L46_runtime_nickname_audit_only", "运行时昵称污染产品角色名", "Faraday 等宿主昵称覆盖张工、李测等配置角色身份", "agent_invocations 分离 role_title、display_name、runtime_nickname", "run-runtime-smoke.rb / run-loop-50-cases.rb"],
  ["L47", "L47_raw_review_visibility", "raw review 不可见", "主控摘要替代角色原始评审，用户无法检查依据", "raw-review-records/<role_key>.md 保留完整原文和审计字段", "run-sop-e2e-smoke.rb / run-loop-50-cases.rb"],
  ["L48", "L48_team_style_consent", "团队风格未经授权进入长期记忆", "同事邮件、会议截图等材料被误写入团队风格或项目记忆", "团队风格反哺必须有授权、用途和存储范围", "run-loop-50-cases.rb"],
  ["L49", "L49_project_asset_pack_export", "项目资料只停留在聊天框", "artifact、决策、评审和角色记忆无法回溯", "Project Asset Pack 导出 Markdown / Obsidian-compatible 项目包", "run-runtime-smoke.rb / run-loop-50-cases.rb"],
  ["L50", "L50_user_decision_after_review", "主控替用户做评审决策", "主控自动采纳、拒绝或关闭评审", "Structured Review Loop 要求用户决定采纳、拒绝、暂缓、补证据或退出评审", "structured-review-loop.md / run-loop-50-cases.rb"]
].each do |badcase_id, case_id, title, symptom, fix_summary, regression_file|
  ledger.seed_badcase(
    badcase_id: badcase_id,
    case_id: case_id,
    title: title,
    symptom: symptom,
    fix_summary: fix_summary,
    regression_file: regression_file,
    status: "locked",
    severity: badcase_id == "L46" || badcase_id == "L47" ? "P0" : "P1"
  )
end

results = []
badcases = []
fixes = []
executed_record_turns = 0
executed_invocations = 0

Dir.mktmpdir("pco-loop-50-") do |dir|
  db = File.join(dir, "product-crew-os.sqlite3")
  workspace = File.join(dir, "workspace")
  vault = File.join(dir, "obsidian")
  project_id = "loop-50"

  run_json(
    ruby, runtime, "init-project",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--name", "Loop 50 Case Test",
    "--description", "50-case loop method validation",
    "--owner", "runtime"
  )

  base_cases.each do |test_case|
    case_id = test_case.fetch("case_id")
    hash = case_hash(case_id: case_id, payload: test_case, files: signature_files)
    if !force && ledger.passed?(case_id, hash)
      skip_result(
        results: results,
        ledger: ledger,
        suite_run_id: suite_run_id,
        case_id: case_id,
        case_type: "44 SOP 基准",
        badcase: "Stage/SOP/Skill/Artifact/Review Session 可写入",
        case_hash: hash,
        source_ref: "loop-50:#{case_id}"
      )
      next
    end

    expected = test_case.fetch("expected")
    stage_id = test_case.fetch("stage_id")
    macro_stage = test_case.fetch("macro_stage")
    primary = expected.fetch("primary_skill")
    fallback = expected.fetch("fallback_skill")
    chosen_skill, status = choose_skill(primary, fallback, bundled)
    artifact_name = Array(expected.fetch("required_artifacts")).first || "#{stage_id}.md"
    roles = (Array(expected["required_roles"]) + Array(expected["triggered_roles"])).uniq
    roles = ["Coach"] if roles.empty?
    content_path = File.join(dir, "#{stage_id}.md")
    File.write(content_path, <<~MARKDOWN)
      ## Loop 50 SOP Case

      - Case: `#{case_id}`
      - Stage: `#{stage_id}`
      - Macro stage: `#{macro_stage}`
      - Actual skill: `#{chosen_skill}`
      - Skill status: `#{status}`
      - Gate: #{expected.fetch("stage_gate")}

      用户输入：

      > #{test_case.fetch("user_input")}
    MARKDOWN

    turn = run_json(
      ruby, runtime, "record-turn",
      "--workspace", workspace,
      "--db", db,
      "--project-id", project_id,
      "--stage-id", stage_id,
      "--macro-stage", macro_stage,
      "--sop-id", stage_id,
      "--user-input", test_case.fetch("user_input"),
      "--route-confidence", "loop_50",
      "--primary-skill", chosen_skill,
      "--fallback-skill", fallback,
      "--skill-status", status,
      "--artifact-name", artifact_name,
      "--artifact-content-file", content_path,
      "--artifact-status", "draft",
      "--gate-status", "conditional_pass",
      "--gate-result", expected.fetch("stage_gate"),
      "--review-roles", roles.join(","),
      "--source-ref", "loop-50:#{case_id}"
    )
    executed_record_turns += 1

    if turn["stage_id"] == stage_id && turn["artifact_id"].to_s != "" && turn["review_session_id"].to_s != ""
      record_result(
        results: results,
        ledger: ledger,
        suite_run_id: suite_run_id,
        case_id: case_id,
        case_type: "44 SOP 基准",
        status: "PASS",
        badcase: "Stage/SOP/Skill/Artifact/Review Session 可写入",
        evidence: "`#{turn["artifact_id"]}`",
        case_hash: hash,
        source_ref: "loop-50:#{case_id}"
      )
    else
      badcases << "#{case_id}: runtime turn did not match expected stage or artifact"
      record_result(
        results: results,
        ledger: ledger,
        suite_run_id: suite_run_id,
        case_id: case_id,
        case_type: "44 SOP 基准",
        status: "FAIL",
        badcase: "Stage/SOP 写入异常",
        evidence: "`#{turn.inspect}`",
        case_hash: hash,
        source_ref: "loop-50:#{case_id}"
      )
    end
  end

  export = run_json(ruby, runtime, "export-obsidian", "--workspace", workspace, "--db", db, "--project-id", project_id, "--output-dir", vault)
  project_path = export.fetch("project_path")

  # Case 45: 非产品问题必须退出产品流程，不应被强行套 SOP。
  case_id = "L45_non_product_task_exit"
  hash = case_hash(case_id: case_id, payload: { check: "non_product_task_exit" }, files: signature_files)
  if !force && ledger.passed?(case_id, hash)
    skip_result(
      results: results,
      ledger: ledger,
      suite_run_id: suite_run_id,
      case_id: case_id,
      case_type: "负例路由",
      badcase: "非产品问题被强行套 SOP",
      case_hash: hash,
      source_ref: "loop-50:#{case_id}"
    )
  else
  readme = File.read(File.join(skill_root, "..", "README.md"))
  non_product_ok = readme.include?("非产品任务") && readme.include?("不会被强行归到 SOP")
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: "负例路由",
    status: non_product_ok ? "PASS" : "FAIL",
    badcase: "非产品问题被强行套 SOP",
    evidence: "`README.md`",
    case_hash: hash,
    source_ref: "loop-50:#{case_id}"
  )
  badcases << "L45_non_product_task_exit: README lacks non-product exit wording" unless non_product_ok
  end

  # Case 46: 运行时昵称只能作为审计字段，不能覆盖配置角色名。
  case_id = "L46_runtime_nickname_audit_only"
  hash = case_hash(case_id: case_id, payload: { role_key: "Tech", runtime_nickname: "Faraday" }, files: signature_files)
  if !force && ledger.passed?(case_id, hash)
    skip_result(
      results: results,
      ledger: ledger,
      suite_run_id: suite_run_id,
      case_id: case_id,
      case_type: "子 Agent 绑定",
      badcase: "运行时昵称覆盖产品角色名",
      case_hash: hash,
      source_ref: "loop-50:#{case_id}"
    )
  else
  packet = run_json(
    ruby, runtime, "build-context-packet",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--role-key", "Tech",
    "--stage-id", "technical_pre_review",
    "--review-question", "检查运行时昵称是否污染产品角色名"
  )
  invocation = run_json(
    ruby, runtime, "record-invocation",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--role-key", "Tech",
    "--runtime-agent-id", "agent-runtime-loop-001",
    "--runtime-nickname", "Faraday",
    "--context-packet-id", packet.fetch("packet_id"),
    "--real", "true",
    "--result", "block"
  )
  executed_invocations += 1
  role_binding_ok =
    invocation["display_name"] == "张工" &&
    invocation["role_title"] == "技术负责人" &&
    invocation["runtime_nickname"] == "Faraday"
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: "子 Agent 绑定",
    status: role_binding_ok ? "PASS" : "FAIL",
    badcase: "运行时昵称覆盖产品角色名",
    evidence: "`agent_invocations`",
    case_hash: hash,
    source_ref: "loop-50:#{case_id}"
  )
  badcases << "L46_runtime_nickname_audit_only: runtime nickname polluted configured role identity" unless role_binding_ok
  fixes << "已通过 `role_title/display_name/runtime_nickname` 分离修复运行时昵称污染问题。" if role_binding_ok
  end

  # Case 47: raw review 必须保留原始文本并可导出。
  case_id = "L47_raw_review_visibility"
  hash = case_hash(case_id: case_id, payload: { role_key: "Tech", stage_id: "formal_requirements_review" }, files: signature_files)
  if !force && ledger.passed?(case_id, hash)
    skip_result(
      results: results,
      ledger: ledger,
      suite_run_id: suite_run_id,
      case_id: case_id,
      case_type: "结构化评审",
      badcase: "主控摘要替代子 Agent 原文",
      case_hash: hash,
      source_ref: "loop-50:#{case_id}"
    )
  else
  session = run_json(
    ruby, runtime, "record-turn",
    "--workspace", workspace,
    "--db", db,
    "--project-id", project_id,
    "--stage-id", "formal_requirements_review",
    "--macro-stage", "cross_functional_review",
    "--sop-id", "formal_requirements_review",
    "--user-input", "验证 raw review 原文是否可追溯",
    "--primary-skill", "stakeholder-alignment-checker",
    "--fallback-skill", "prd-critic",
    "--artifact-name", "Raw Review Visibility Check",
    "--artifact-content", "This artifact validates raw review visibility.",
    "--review-roles", "Tech",
    "--gate-status", "conditional_pass",
    "--gate-result", "raw review should be visible"
  )
  executed_record_turns += 1
  raw_review_path = Dir[File.join(workspace, "memory", "projects", project_id, "raw-review-records", session.fetch("review_session_id"), "*.md")].first
  raw_review_ok = raw_review_path && File.read(raw_review_path).include?("Raw Review: 张工 / Tech") && File.read(raw_review_path).include?("原始评审记录")
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: "结构化评审",
    status: raw_review_ok ? "PASS" : "FAIL",
    badcase: "主控摘要替代子 Agent 原文",
    evidence: raw_review_path ? "`#{File.basename(raw_review_path)}`" : "`missing`",
    case_hash: hash,
    source_ref: "loop-50:#{case_id}"
  )
  badcases << "L47_raw_review_visibility: raw review file missing role display name or original record" unless raw_review_ok
  fixes << "raw-review-records 已保留配置显示名、运行时昵称审计字段和完整原始评审段落。" if raw_review_ok
  end

  # Case 48: 真实团队材料必须授权后才能进入角色风格或项目记忆。
  case_id = "L48_team_style_consent"
  hash = case_hash(case_id: case_id, payload: { check: "team_style_consent" }, files: signature_files)
  if !force && ledger.passed?(case_id, hash)
    skip_result(
      results: results,
      ledger: ledger,
      suite_run_id: suite_run_id,
      case_id: case_id,
      case_type: "记忆边界",
      badcase: "同事材料未授权进入长期角色记忆",
      case_hash: hash,
      source_ref: "loop-50:#{case_id}"
    )
  else
  consent_files = [
    File.join(skill_root, "references", "experience", "agent-customization-and-team-style.md"),
    File.join(skill_root, "references", "subagent-memory-runtime-contract.md"),
    File.join(skill_root, "config", "crew-personas.yaml")
  ]
  consent_text = consent_files.select { |path| File.exist?(path) }.map { |path| File.read(path) }.join("\n")
  consent_ok = consent_text.include?("consent") || consent_text.include?("授权")
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: "记忆边界",
    status: consent_ok ? "PASS" : "FAIL",
    badcase: "同事材料未授权进入长期角色记忆",
    evidence: "`agent-customization-and-team-style.md`",
    case_hash: hash,
    source_ref: "loop-50:#{case_id}"
  )
  badcases << "L48_team_style_consent: team-style source materials lack consent gate" unless consent_ok
  end

  # Case 49: Project Asset Pack 必须能导出到可读 Markdown/Obsidian-compatible 目录。
  case_id = "L49_project_asset_pack_export"
  hash = case_hash(case_id: case_id, payload: { check: "project_asset_pack_export" }, files: signature_files)
  if !force && ledger.passed?(case_id, hash)
    skip_result(
      results: results,
      ledger: ledger,
      suite_run_id: suite_run_id,
      case_id: case_id,
      case_type: "项目资产包",
      badcase: "项目资料只留在聊天框，未进入可读项目包",
      case_hash: hash,
      source_ref: "loop-50:#{case_id}"
    )
  else
  export = run_json(ruby, runtime, "export-obsidian", "--workspace", workspace, "--db", db, "--project-id", project_id, "--output-dir", vault)
  project_path = export.fetch("project_path")
  asset_pack_ok =
    File.exist?(File.join(project_path, "00_项目首页.md")) &&
    File.exist?(File.join(project_path, "_项目账本", "decision-log.md")) &&
    File.exist?(File.join(project_path, "_项目账本", "review-items.yaml")) &&
    Dir[File.join(project_path, "_项目账本", "raw-review-records", "**", "*.md")].any?
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: "项目资产包",
    status: asset_pack_ok ? "PASS" : "FAIL",
    badcase: "项目资料只留在聊天框，未进入可读项目包",
    evidence: "`#{project_path}`",
    case_hash: hash,
    source_ref: "loop-50:#{case_id}"
  )
  badcases << "L49_project_asset_pack_export: exported project pack missing home, ledgers, or raw review records" unless asset_pack_ok
  end

  # Case 50: Structured Review Loop 必须把用户决策放在主控收束之后，不能主控替用户采纳。
  case_id = "L50_user_decision_after_review"
  hash = case_hash(case_id: case_id, payload: { check: "user_decision_after_review" }, files: signature_files)
  if !force && ledger.passed?(case_id, hash)
    skip_result(
      results: results,
      ledger: ledger,
      suite_run_id: suite_run_id,
      case_id: case_id,
      case_type: "Review Loop",
      badcase: "主控替用户采纳/拒绝评审建议",
      case_hash: hash,
      source_ref: "loop-50:#{case_id}"
    )
  else
  review_loop = File.read(File.join(skill_root, "references", "structured-review-loop.md"))
  decision_loop_ok =
    review_loop.include?("用户决定采纳、拒绝、暂缓") &&
    review_loop.include?("不能替用户决策") &&
    review_loop.include?("用户确认后关闭")
  record_result(
    results: results,
    ledger: ledger,
    suite_run_id: suite_run_id,
    case_id: case_id,
    case_type: "Review Loop",
    status: decision_loop_ok ? "PASS" : "FAIL",
    badcase: "主控替用户采纳/拒绝评审建议",
    evidence: "`structured-review-loop.md`",
    case_hash: hash,
    source_ref: "loop-50:#{case_id}"
  )
  badcases << "L50_user_decision_after_review: structured review loop lacks user decision/exit guard" unless decision_loop_ok
  end

  # Cross-case database checks.
  expected_counts = {
    "sop_runs" => executed_record_turns,
    "skill_runs" => executed_record_turns,
    "artifacts" => executed_record_turns,
    "review_sessions" => executed_record_turns,
    "raw_review_records" => executed_record_turns,
    "agent_invocations" => executed_record_turns + executed_invocations,
    "review_items" => executed_record_turns,
    "context_packets" => executed_record_turns + executed_invocations
  }
  expected_counts.each do |table, minimum|
    next if minimum.zero?

    actual = query_value(db, "SELECT COUNT(*) AS count FROM #{table};").to_i
    if actual < minimum
      badcases << "database count: #{table} expected at least #{minimum}, got #{actual}"
    end
  end

  misbound = query_value(db, "SELECT COUNT(*) AS count FROM agent_invocations WHERE role_key IN ('Coach','Biz','Research','CS','Customer','Design','Tech','Data','QA','Legal','Ops') AND display_name = role_key;").to_i
  missing_title = query_value(db, "SELECT COUNT(*) AS count FROM agent_invocations WHERE role_key IN ('Coach','Biz','Research','CS','Customer','Design','Tech','Data','QA','Legal','Ops') AND role_title = '';").to_i
  if misbound > 0
    badcases << "agent invocation role binding: #{misbound} known roles still use role_key as display_name"
  end
  if missing_title > 0
    badcases << "agent invocation role title: #{missing_title} known roles missing role_title"
  end

  pass_count = results.count { |row| row[:status] == "PASS" }
  skip_count = results.count { |row| row[:status] == "SKIP_PASS" }
  fail_count = results.count { |row| row[:status] == "FAIL" }
  actual_executed_count = pass_count + fail_count
  if release_gate && (pass_count != results.length || skip_count.positive? || fail_count.positive?)
    badcases << "release gate requires a fresh full run: expected #{results.length} fresh PASS cases, got pass=#{pass_count}, skip=#{skip_count}, fail=#{fail_count}"
  end

  FileUtils.mkdir_p(results_dir)
  report = [
    "# Product Crew OS 50 个 Loop 测试报告",
    "",
    "- Suite: `loop-50-cases`",
    "- 总用例数: `#{results.length}`",
    "- 通过: `#{pass_count}`",
    "- 跳过已通过: `#{skip_count}`",
    "- 失败: `#{fail_count}`",
    "- 本次实际执行: `#{actual_executed_count}`",
    "- Test Ledger: `#{ledger.disabled? ? "disabled" : ledger.db}`",
    "- Runner version: `#{RUNNER_VERSION}`",
    "- Git SHA: `#{git_sha}`",
    "- Force rerun: `#{force ? "true" : "false"}`",
    "- Release gate: `#{release_gate ? "true" : "false"}`",
    "- Suite run id: `#{suite_run_id}`",
    "- Runtime DB: `#{db}`",
    "- Project Workspace: `#{File.join(workspace, "memory", "projects", project_id)}`",
    "- Obsidian-compatible export: `#{project_path}`",
    "",
    "## 测试方法",
    "",
    "本轮采用 loop 方法：每个 case 都按 `输入 -> 预期 Stage/SOP/Skill/Agent/Artifact/Gate -> Runtime 写入 -> 断言 -> 记录证据 -> Bad Case 归档` 执行。44 个用例来自标准 SOP 基准集，6 个用例来自近期真实测试暴露的高风险 Bad Case。默认启用本地 SQLite 测试账本，已通过且指纹未变化的 case 会标记为 `SKIP_PASS`。",
    "",
    "## 50 个用例结果",
    "",
    markdown_table(results),
    "",
    "## Bad Case 记录",
    ""
  ]
  if badcases.empty?
    report << "- 本轮未发现新的失败 Bad Case。近期已知 Bad Case 已被回归锁定：运行时昵称污染角色名、raw review 不可见、非产品任务强行套 SOP。"
  else
    badcases.each { |badcase| report << "- #{badcase}" }
  end
  report += [
    "",
    "## 已修正 / 已回归锁定",
    ""
  ]
  if fixes.empty? && skip_count.positive?
    report << "- 本轮命中的已修复 Bad Case 均由测试账本跳过，未重复执行。"
  else
    fixes.uniq.each { |fix| report << "- #{fix}" }
  end
  if fail_count == 0 && executed_record_turns.positive?
    report << "- 本次执行的 SOP 均可写入 runtime，并产生 stage、skill、artifact、context packet、invocation ledger、review item 和 raw review record。"
  elsif fail_count == 0 && skip_count.positive?
    report << "- 本轮未重复执行已通过 case；结果由测试账本中的 PASS 记录和当前指纹共同确认。"
  end
  report += [
    "",
    "## 下一步建议",
    "",
    "- 将本脚本加入发布前质检清单，与 `run-runtime-smoke.rb`、`run-sop-e2e-smoke.rb` 一起执行。",
    "- 下一轮可把 50 个 case 拆成 P0/P1/P2 分层，并接入更真实的多轮用户纠错样本。",
    "- 如果迁移到 Coze/Dify/LangGraph，需要把 L46/L47 作为宿主适配验收项，确保真实子 Bot 名称和产品角色绑定不混。"
  ]
  File.write(report_path, report.join("\n"))
  suite_status = badcases.empty? ? "PASS" : "FAIL"
  ledger.finish_suite_run(
    suite_run_id: suite_run_id,
    status: suite_status,
    total_count: results.length,
    pass_count: pass_count,
    fail_count: fail_count,
    skip_count: skip_count,
    actual_executed_count: actual_executed_count,
    report_path: report_path
  )

  if badcases.empty?
    puts "run-loop-50-cases: PASS"
    puts "cases: #{results.length}"
    puts "skipped: #{skip_count}"
    puts "ledger: #{ledger.disabled? ? "disabled" : ledger.db}"
    puts "report: #{report_path}"
  else
    warn "run-loop-50-cases: FAIL"
    warn "report: #{report_path}"
    badcases.each { |badcase| warn "- #{badcase}" }
    exit 1
  end
end
