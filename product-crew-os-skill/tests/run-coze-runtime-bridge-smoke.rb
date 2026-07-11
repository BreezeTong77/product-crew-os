#!/usr/bin/env ruby

require "json"
require "net/http"
require "rbconfig"
require "socket"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
BRIDGE = File.join(ROOT, "runtime", "pco_coze_bridge.rb")

def assert(errors, condition, message)
  errors << message unless condition
end

def free_port
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  server.close
  port
end

def request(port, method, path, token, payload = nil)
  client = Net::HTTP.new("127.0.0.1", port, nil)
  request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
  request = request_class.new(path)
  request["Authorization"] = "Bearer #{token}"
  if payload
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)
  end
  response = client.request(request)
  [response.code.to_i, JSON.parse(response.body)]
end

def wait_for_health(port, token)
  40.times do
    status, payload = request(port, :get, "/health", token)
    return payload if status == 200
  rescue Errno::ECONNREFUSED
    sleep 0.1
  end
  raise "bridge did not become ready"
end

errors = []
Dir.mktmpdir("pco-coze-bridge-") do |dir|
  port = free_port
  token = "coze-bridge-test-token"
  workspace = File.join(dir, "workspace")
  exports = File.join(dir, "exports")
  log = File.join(dir, "bridge.log")
  environment = {
    "PCO_RUNTIME_TOKEN" => token,
    "PCO_RUNTIME_PORT" => port.to_s,
    "PCO_RUNTIME_WORKSPACE" => workspace,
    "PCO_RUNTIME_DB" => File.join(workspace, "product-crew-os.sqlite3"),
    "PCO_RUNTIME_EXPORT_ROOT" => exports,
    "PCO_COZE_SUBAGENT_DELEGATE" => "workflow_callback",
    "PCO_EMBEDDING_PROVIDER" => "local_hash_dry_run"
  }
  pid = Process.spawn(environment, RbConfig.ruby, BRIDGE, out: log, err: log)
  begin
    health = wait_for_health(port, token)
    assert(errors, health["status"] == "ok", "bridge health endpoint did not return ok")

    status, handshake = request(port, :post, "/v1/handshake", token, {})
    assert(errors, status == 200, "capability handshake request failed")
    assert(errors, handshake.dig("configured_capabilities", "subagent_delegate", "configured") == true, "handshake did not expose Coze callback delegate configuration")
    assert(errors, handshake["runtime_status"] == "runtime_degraded", "handshake should remain degraded without real embedding configuration")

    status, project = request(port, :post, "/v1/projects", token, {
      project_id: "coze_demo",
      name: "Coze Runtime Bridge Demo",
      description: "Bridge smoke test"
    })
    assert(errors, status == 201 && project["project_id"] == "coze_demo", "project creation through bridge failed")

    status, rag_ingest = request(port, :post, "/v1/rag/ingest", token, {
      namespace: "pco_rules",
      scope: "product_rule_memory",
      source_ref: "fixture:coze-bridge-rag",
      title: "Coze Bridge RAG Fixture",
      content: "审核工作台需要真实 RAG 检索。",
      metadata: { stage_id: "mvp_scope", case_id: "coze_bridge_rag" }
    })
    assert(errors, status == 201 && rag_ingest["created"] == 1, "RAG ingestion through bridge failed")
    status, rag_retrieval = request(port, :post, "/v1/rag/retrieve", token, {
      query: "真实 RAG 检索",
      namespace: "pco_rules",
      allowed_scopes: "product_rule_memory"
    })
    assert(errors, status == 200 && rag_retrieval.fetch("candidates").first&.fetch("source_ref") == "fixture:coze-bridge-rag", "RAG retrieval through bridge lost the source ref")
    assert(errors, rag_retrieval["real_embedding_performed"] == false, "hash bridge test provider incorrectly claimed real embedding")

    status, route = request(port, :post, "/v1/routes", token, {
      project_id: "coze_demo",
      user_input: "先做 MVP，砍范围。"
    })
    assert(errors, status == 200 && route["route_decision_id"].to_s != "", "route trace was not written through bridge")

    status, skill_execution = request(port, :post, "/v1/skills/execute", token, {
      skill_id: "product-discovery",
      input: {
        assumptions: [{ statement: "审核员会采纳 AI 建议", category: "desirability", risk: 0.9, certainty: 0.2 }]
      }
    })
    assert(errors, status == 200 && skill_execution["execution_status"] == "executed", "bridge did not execute registered external Skill driver")
    assert(errors, skill_execution.dig("execution_proof", "exit_code") == 0, "bridge skill execution did not return process proof")

    status, unavailable_skill = request(port, :post, "/v1/skills/execute", token, { skill_id: "scope-cutting", input: {} })
    assert(errors, status == 200 && unavailable_skill["execution_status"] == "deployment_required" && unavailable_skill["must_notify_user"] == true, "bridge did not require a user deployment notice for methodology-only Skill")

    status, mcp_skill = request(port, :post, "/v1/skills/execute", token, { skill_id: "pencil-design", input: {} })
    assert(errors, status == 200 && mcp_skill.dig("deployment_notice", "authorization_required") == true, "bridge did not require authorization for MCP Skill deployment")

    status, host_skill_execution = request(port, :post, "/v1/skills/host-callback", token, {
      project_id: "coze_demo",
      stage_id: "mvp_scope",
      skill_id: "scope-cutting",
      runtime_model_id: "coze-llm-production-node",
      host_run_id: "coze-workflow-run-001",
      raw_output: "真实 Coze LLM 节点完成范围裁剪并返回该原始输出。",
      observed_actions_json: "[\"read_artifacts\",\"draft_artifact\"]",
      source_ref: "coze:workflow:scope-cutting"
    })
    assert(errors, status == 201 && host_skill_execution["execution_id"].to_s != "", "bridge did not persist real host Skill callback evidence")

    status, route_bypass = request(port, :post, "/v1/turns", token, {
      project_id: "coze_demo",
      stage_id: "mvp_scope",
      primary_skill: "scope-cutting",
      artifact_name: "Route Bypass Draft"
    })
    assert(errors, status == 422 && route_bypass["error"] == "runtime_rejected", "bridge accepted a turn without a persisted route decision")

    status, turn = request(port, :post, "/v1/turns", token, {
      project_id: "coze_demo",
      stage_id: "mvp_scope",
      route_decision_id: route["route_decision_id"],
      sop_id: "mvp_scope",
      user_input: "先做 MVP，砍范围。",
      primary_skill: "scope-cutting",
      fallback_skill: "shape-up",
      skill_status: "completed",
      skill_execution_id: host_skill_execution["execution_id"],
      skill_execution: {
        contract_ref: "coze-smoke:scope-cutting",
        skill_id: "scope-cutting",
        execution_mode: "external_workflow",
        allowed_stage_ids: ["mvp_scope"],
        capability_scope: ["范围裁剪", "取舍分析"],
        approved_actions: ["read_artifacts", "draft_artifact"],
        observed_actions: ["read_artifacts", "draft_artifact"],
        control_boundary: {
          may_change_stage: false,
          may_decide_gate: false,
          may_write_project_memory: false,
          may_call_agents: false
        },
        output_evidence: {
          artifact_name: "MVP Scope",
          source_ref: "coze-skill:scope-cutting:smoke"
        }
      },
      artifact_name: "MVP Scope",
      artifact_content: "第一阶段只验证一条核心流程。",
      gate_status: "conditional_pass",
      review_question: "检查范围、业务价值和技术边界。"
    })
    assert(errors, status == 201, "turn creation through bridge failed")
    assert(errors, turn["gate_status"] == "awaiting_external_review", "bridge allowed a reviewed stage to pass before callbacks")
    assert(errors, turn["review_mode"] == "standard_sop", "bridge did not enter the route-controlled standard SOP review mode")
    assert(errors, turn.dig("skill_execution", "contract_status") == "validated", "bridge did not forward the external skill contract")
    roles = turn.fetch("roles", [])
    expected_roles = (Array(route["required_roles"]) + Array(route["triggered_roles"])).reject { |role| role == "Coach" }.uniq.sort
    assert(errors, roles.map { |role| role["role_key"] }.sort == expected_roles, "bridge did not prepare the route-required and route-triggered roles")
    assert(errors, roles.all? { |role| role["context_packet_quality"] == "complete" }, "bridge did not build complete persona packets")
    assert(errors, roles.all? { |role| role["invocation_id"].to_s.empty? }, "bridge created a simulated invocation before real Coze callbacks")

    artifact_id = turn.fetch("artifact_id")
    session_id = turn.fetch("review_session_id")

    status, overreach_project = request(port, :post, "/v1/projects", token, {
      project_id: "coze_overreach",
      name: "Coze External Skill Overreach"
    })
    assert(errors, status == 201 && overreach_project["project_id"] == "coze_overreach", "bridge did not create isolated overreach test project")
    status, overreach_route = request(port, :post, "/v1/routes", token, {
      project_id: "coze_overreach",
      user_input: "先做 MVP，砍范围。"
    })
    assert(errors, status == 200 && overreach_route["route_decision_id"].to_s != "", "bridge did not persist the overreach route decision")
    status, overreach_turn = request(port, :post, "/v1/turns", token, {
      project_id: "coze_overreach",
      stage_id: "mvp_scope",
      route_decision_id: overreach_route["route_decision_id"],
      sop_id: "mvp_scope",
      user_input: "先做 MVP，砍范围。",
      primary_skill: "scope-cutting",
      skill_status: "completed",
      skill_execution: {
        skill_id: "scope-cutting",
        execution_mode: "external_workflow",
        allowed_stage_ids: ["mvp_scope"],
        capability_scope: ["范围裁剪"],
        approved_actions: ["draft_artifact", "decide_gate"],
        observed_actions: ["draft_artifact", "decide_gate"],
        control_boundary: {
          may_change_stage: false,
          may_decide_gate: true,
          may_write_project_memory: false,
          may_call_agents: false
        },
        output_evidence: {
          artifact_name: "Overreach Skill Draft",
          source_ref: "coze-skill:scope-cutting:overreach"
        }
      },
      artifact_name: "Overreach Skill Draft",
      artifact_content: "Skill 的草稿保留，但不能让它决定阶段门。",
      gate_status: "conditional_pass"
    })
    assert(errors, status == 201, "bridge did not retain overreaching skill draft")
    assert(errors, overreach_turn["gate_status"] == "blocked_runtime_preflight", "bridge allowed an overreaching skill to pass the gate")
    assert(errors, overreach_turn.dig("skill_execution", "overreach_detected") == true, "bridge did not record external skill overreach")

    status, unindexed_evidence = request(port, :post, "/v1/rag/evidence", token, {
      project_id: "coze_overreach",
      stage_run_id: overreach_turn.fetch("stage_run_id"),
      artifact_id: overreach_turn.fetch("artifact_id"),
      source_refs: "fixture:not-indexed"
    })
    assert(errors, status == 201 && unindexed_evidence["gate_evidence_eligible"] == false, "bridge accepted an unindexed RAG source as gate evidence")
    assert(errors, unindexed_evidence.fetch("evidence").first.fetch("reason") == "source_not_indexed", "bridge did not preserve the unindexed evidence reason")

    roles.each do |role|
      role_key = role.fetch("role_key")
      status, invalid_callback = request(port, :post, "/v1/reviews/callback", token, {
        project_id: "coze_demo",
        session_id: session_id,
        role_key: role_key,
        stage_id: "mvp_scope",
        artifact_id: artifact_id,
        context_packet_id: role.fetch("packet_id"),
        raw_review: "This callback has no runtime bot id.",
        conclusion: "conditional_pass"
      })
      assert(errors, status == 422 && invalid_callback["error"] == "runtime_rejected", "bridge accepted a sub-Bot callback without runtime_agent_id")

      status, callback = request(port, :post, "/v1/reviews/callback", token, {
        project_id: "coze_demo",
        session_id: session_id,
        role_key: role_key,
        stage_id: "mvp_scope",
        artifact_id: artifact_id,
        context_packet_id: role.fetch("packet_id"),
        runtime_agent_id: "coze_bot_#{role_key.downcase}_001",
        runtime_nickname: "Coze #{role_key}",
        raw_review: "#{role_key} returned this raw review through the external callback contract.",
        conclusion: "conditional_pass",
        review_items: [{
          comment: "#{role_key} requires one follow-up condition.",
          priority: "should_fix",
          recommendation: "Record the condition in the next artifact revision.",
          status: "open"
        }]
      })
      assert(errors, status == 201 && callback["real_invocation_performed"] == true, "bridge did not record a real callback for #{role_key}")
      assert(errors, callback.dig("raw_review_record", "record_id").to_s != "", "bridge did not persist raw review for #{role_key}")
    end

    status, unbound_gate = request(port, :post, "/v1/gates/finalize", token, {
      project_id: "coze_demo",
      stage_id: "mvp_scope",
      artifact_id: artifact_id,
      review_session_id: session_id,
      requested_gate_status: "conditional_pass",
      user_confirmed: true
    })
    assert(errors, status == 422 && unbound_gate["error"] == "runtime_rejected", "bridge finalized a gate without the immutable stage_run_id")

    status, gate = request(port, :post, "/v1/gates/finalize", token, {
      project_id: "coze_demo",
      stage_id: "mvp_scope",
      artifact_id: artifact_id,
      stage_run_id: turn.fetch("stage_run_id"),
      review_session_id: session_id,
      requested_gate_status: "conditional_pass",
      user_confirmed: true,
      decision_note: "User reviewed the conditions."
    })
    assert(errors, status == 200 && gate["gate_status"] == "conditional_pass", "bridge did not finalize the gate after real callback evidence and user confirmation")

    status, export = request(port, :post, "/v1/exports/obsidian", token, { project_id: "coze_demo" })
    assert(errors, status == 201, "obsidian export through bridge failed")
    project_path = export["project_path"].to_s
    assert(errors, File.exist?(File.join(project_path, "_项目账本", "routing", "stage-route-decision.jsonl")), "bridge export missing route trace")
    assert(errors, Dir[File.join(project_path, "_项目账本", "raw-review-records", "**", "*.md")].length == roles.length, "bridge export missing raw review records")

    counts = JSON.parse(`sqlite3 -json #{File.join(workspace, "product-crew-os.sqlite3").inspect} "SELECT real_invocation_performed, COUNT(*) AS count FROM agent_invocations GROUP BY real_invocation_performed;"`)
    assert(errors, counts == [{ "real_invocation_performed" => 1, "count" => roles.length }], "bridge ledger contains simulated invocations in the external callback path")
  ensure
    Process.kill("TERM", pid) rescue nil
    Process.wait(pid) rescue nil
  end
end

if errors.empty?
  puts "run-coze-runtime-bridge-smoke: PASS"
else
  warn "run-coze-runtime-bridge-smoke: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
