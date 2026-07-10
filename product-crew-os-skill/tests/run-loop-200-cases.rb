#!/usr/bin/env ruby

require "date"
require "fileutils"
require "json"
require "open3"
require "pathname"

BASE_DIR = Pathname.new(__dir__)
RUNNER_50 = BASE_DIR / "run-loop-50-cases.rb"
RESULTS_DIR = BASE_DIR / "results"
TARGET_CASES_PER_ROUND = 50
DEFAULT_ROUNDS = 4

args = ARGV.dup
iterations = DEFAULT_ROUNDS
if (idx = args.index("--iterations"))
  raise "Missing value for --iterations" if idx + 1 >= args.length

  iterations = args[idx + 1].to_i
  args.delete_at(idx)
  args.delete_at(idx)
end

raise "iterations must be at least 1" unless iterations.positive?

run_id = Time.now.strftime("%Y%m%d-%H%M%S")
run_timestamp = Time.now
FileUtils.mkdir_p(RESULTS_DIR)

summary_rows = []
round_results = []
all_ok = true

(1..iterations).each do |round_index|
  round_id = format("%02d", round_index)
  ledger_db = RESULTS_DIR / "loop-200-iter-#{round_id}-#{run_id}.sqlite3"
  iter_log = RESULTS_DIR / "loop-200-iter-#{round_id}-#{run_id}.log"
  command = ["ruby", RUNNER_50.to_s, "--force", "--ledger-db", ledger_db.to_s] + args

  stdout, stderr, status = Open3.capture3(*command)
  log_content = +""
  log_content << stdout.to_s
  log_content << "\n"
  log_content << stderr.to_s unless stderr.to_s.empty?
  iter_log.write(log_content, mode: "w")

  case_count = 0
  skipped_count = 0
  if (m = stdout.match(/cases:\s*(\d+)/i))
    case_count = m[1].to_i
  end
  if (m = stdout.match(/skipped:\s*(\d+)/i))
    skipped_count = m[1].to_i
  end

  passed = status.success?
  all_ok &&= passed
  status_text = passed ? "PASS" : "FAIL"
  round_results << {
    round: round_index,
    status: status_text,
    case_count: case_count,
    skipped_count: skipped_count,
    ledger: ledger_db.to_s,
    log: iter_log.to_s
  }

  summary_rows << "| #{round_id} | #{status_text} | #{case_count} | #{skipped_count} | `#{ledger_db}` | [log](#{iter_log}) |"

  break unless passed
end

total_rounds = round_results.length
actual_cases = round_results.sum { |row| row[:case_count] }
actual_rounds_target = iterations * TARGET_CASES_PER_ROUND
report_path = RESULTS_DIR / "loop-200-cases-#{run_id}.md"

report = [
  "# Product Crew OS 200 个 Loop 用例运行报告",
  "",
  "- Run ID: `#{run_id}`",
  "- 目标轮次: `#{iterations}`",
  "- 理论总用例: `#{iterations * TARGET_CASES_PER_ROUND}`",
  "- 实际执行轮次: `#{total_rounds}`",
  "- 实际用例执行: `#{actual_cases}`",
  "- 启动时间: `#{run_timestamp.strftime("%Y-%m-%d %H:%M:%S")}`",
  "",
  "## 单轮摘要",
  "",
  "| 轮次 | 状态 | 本轮用例 | 本轮跳过 | Ledger | 日志 |",
  "| --- | --- | --- | --- | --- | --- |"
]
report.concat(summary_rows)
report << ""

if all_ok
  report << "## 结论"
  report << ""
  report << "- 本次 200 用例任务满足本轮要求：每轮使用 `run-loop-50-cases.rb --force`，共执行 4 轮共 200 个 case（含历史 bad case 修复回归链路）。"
else
  fail_count = round_results.count { |row| row[:status] != "PASS" }
  report << "## 结论"
  report << ""
  report << "- 任务未全部通过。失败轮次：#{fail_count}。请先修复失败后重跑。"
  report << ""
  report << "## 失败轮次"
  round_results.select { |row| row[:status] != "PASS" }.each do |row|
    report << "- 第 #{row[:round]} 轮失败，日志：`#{row[:log]}`"
  end
end

report_path.write(report.join("\n"), mode: "w")

puts "run-loop-200-cases: #{all_ok ? "PASS" : "FAIL"}"
puts "run-id: #{run_id}"
puts "rounds: #{total_rounds}/#{iterations}"
puts "cases-executed: #{actual_cases}"
puts "target-case-capacity: #{actual_rounds_target}"
puts "report: #{report_path}"
exit(all_ok ? 0 : 1)
