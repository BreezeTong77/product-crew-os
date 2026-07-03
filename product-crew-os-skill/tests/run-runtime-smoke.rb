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
    [ruby, runtime, "write-review-item", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--reviewer-name", "Tech Reviewer", "--comment", "Check write failure visibility.", "--recommendation", "Exit non-zero and keep event trail.", "--stage-id", "requirement_analysis", "--source-ref", "smoke:review"],
    [ruby, runtime, "write-agent-memory", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--summary", "Tech watches database writes, rollback, and error visibility.", "--source-ref", "smoke:review", "--confidence", "confirmed"]
  ]

  parallel.map do |cmd|
    Thread.new { run_cmd(errors, *cmd) }
  end.each(&:join)

  packet = run_cmd(errors, ruby, runtime, "build-context-packet", "--workspace", workspace, "--db", db, "--project-id", project_id, "--role-key", "Tech", "--stage-id", "requirement_analysis", "--review-question", "Check runtime MVP risk")
  assert(errors, File.exist?(packet["path"].to_s), "runtime did not write context packet")

  export = run_cmd(errors, ruby, runtime, "export-obsidian", "--workspace", workspace, "--db", db, "--project-id", project_id, "--output-dir", vault)
  project_path = export["project_path"].to_s
  assert(errors, File.exist?(File.join(project_path, "00_项目首页.md")), "obsidian export missing project home")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "decision-log.md")), "obsidian export missing decision log")
  assert(errors, File.exist?(File.join(project_path, "_项目账本", "review-items.yaml")), "obsidian export missing review items")
  assert(errors, File.exist?(File.join(project_path, "_团队记忆", "tech.md")), "obsidian export missing role memory")

  query = "select 'projects' as table_name, count(*) as count from projects union all select 'artifacts', count(*) from artifacts union all select 'decisions', count(*) from decisions union all select 'review_items', count(*) from review_items union all select 'agent_memories', count(*) from agent_memories union all select 'context_packets', count(*) from context_packets;"
  stdout, stderr, status = Open3.capture3("sqlite3", "-json", db, query)
  if status.success?
    counts = JSON.parse(stdout).each_with_object({}) { |row, memo| memo[row.fetch("table_name")] = row.fetch("count").to_i }
    %w[projects artifacts decisions review_items agent_memories context_packets].each do |table|
      assert(errors, counts[table].to_i >= 1, "runtime sqlite table #{table} is empty")
    end
  else
    errors << "sqlite count query failed: #{stderr}"
  end
end

if errors.empty?
  puts "run-runtime-smoke: PASS"
else
  warn "run-runtime-smoke: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
