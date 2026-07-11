#!/usr/bin/env ruby

require "json"
require "open3"
require "rbconfig"

skill_root = File.expand_path("..", __dir__)
runtime = File.join(skill_root, "runtime", "pco_runtime.rb")
errors = []

def execute(runtime, skill_id, input)
  stdout, stderr, status = Open3.capture3(
    RbConfig.ruby, runtime, "execute-skill",
    "--skill-id", skill_id,
    "--input-json", JSON.generate(input)
  )
  raise "#{skill_id} failed: #{stderr}\n#{stdout}" unless status.success?

  JSON.parse(stdout)
end

begin
  discovery = execute(
    runtime,
    "product-discovery",
    "assumptions" => [
      { "statement" => "审核员会采纳 AI 建议", "category" => "desirability", "risk" => 0.9, "certainty" => 0.2 }
    ]
  )
  errors << "product-discovery command driver did not execute" unless discovery["execution_status"] == "executed"
  errors << "product-discovery command driver has no exit proof" unless discovery.dig("execution_proof", "exit_code") == 0
  errors << "product-discovery output is not the expected prioritization plan" unless discovery["stdout"].to_s.include?("prioritized_assumption_test_plan")

  experiment = execute(runtime, "trustworthy-experiments", "baseline" => 0.1, "mde_absolute" => 0.02)
  errors << "trustworthy-experiments command driver did not execute" unless experiment["execution_status"] == "executed"
  errors << "trustworthy-experiments output is missing sample size" unless experiment["stdout"].to_s.include?("Needed total")

  methodology = execute(runtime, "scope-cutting", {})
  errors << "methodology-only skill was falsely reported as executed" unless methodology["execution_status"] == "deployment_required" && methodology["reason"] == "host_callback_required"
  errors << "methodology-only skill did not require a user deployment notice" unless methodology["must_notify_user"] == true && methodology.dig("deployment_notice", "required_steps").any?

  mcp = execute(runtime, "pencil-design", {})
  errors << "MCP skill did not request deployment and authorization" unless mcp["execution_status"] == "deployment_required" && mcp.dig("deployment_notice", "authorization_required") == true

  implicit_prompt = execute(runtime, "pm-workbench", "request" => "帮我判断一个产品想法下一步该做什么")
  errors << "bundled methodology skill did not enter the local prompt execution path" unless %w[executed deployment_required failed].include?(implicit_prompt["execution_status"])
  errors << "bundled methodology skill did not identify its prompt driver" unless implicit_prompt["driver"] == "ollama_prompt" || implicit_prompt["reason"] == "ollama_prompt"
rescue StandardError => error
  errors << error.message
end

if errors.empty?
  puts "run-skill-executor-smoke: PASS"
else
  warn "run-skill-executor-smoke: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
