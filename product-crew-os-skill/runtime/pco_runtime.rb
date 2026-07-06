#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "time"
require "yaml"
require_relative "stage_router"

class ProductCrewRuntime
  FLOW_DIRS = {
    "project_intake" => "01_机会发现",
    "opportunity_discovery" => "01_机会发现",
    "user_research" => "02_用户研究",
    "problem_framing" => "03_问题定义",
    "problem_definition" => "03_问题定义",
    "requirement_analysis" => "04_需求分析",
    "prioritization" => "04_需求分析",
    "solution_design" => "05_方案设计",
    "solution_exploration" => "05_方案设计",
    "low_fi_prototype" => "05_方案设计",
    "prd_drafting" => "06_PRD与评审",
    "formal_requirements_review" => "06_PRD与评审",
    "delivery_planning" => "07_交付规划",
    "launch_readiness" => "08_上线准备",
    "launch_monitoring" => "09_上线监控",
    "post_launch_review" => "10_复盘迭代",
    "iteration_planning" => "10_复盘迭代"
  }.freeze

  def initialize(db_path:, workspace:)
    @db_path = File.expand_path(db_path)
    @workspace = File.expand_path(workspace)
    FileUtils.mkdir_p(File.dirname(@db_path))
    FileUtils.mkdir_p(@workspace)
    apply_schema
  end

  def init_project(project_id:, name:, description: "", owner: "")
    now = timestamp
    project_dir = project_dir(project_id)
    create_project_workspace(project_id, name)
    exec_sql(<<~SQL)
      INSERT OR IGNORE INTO projects
        (project_id, name, description, owner, workspace_path, created_at, updated_at)
      VALUES
        (#{q(project_id)}, #{q(name)}, #{q(description)}, #{q(owner)}, #{q(project_dir)}, #{q(now)}, #{q(now)});
    SQL
    record_event(project_id, "project_created", { name: name, owner: owner })
    write_project_state(project_id)
    refresh_all_ledgers(project_id)
    puts_json(project_id: project_id, workspace: project_dir, db: @db_path)
  end

  def save_artifact(project_id:, name:, stage_id:, sop_id: "", artifact_type: "markdown", status: "draft", content_file: nil, content: nil, source_ref: "", emit: true)
    ensure_project!(project_id)
    now = timestamp
    body = content || (content_file ? File.read(content_file) : "")
    raise "artifact content is empty" if body.strip.empty?

    existing = query_one("SELECT * FROM artifacts WHERE project_id = #{q(project_id)} AND name = #{q(name)} ORDER BY created_at DESC LIMIT 1;")
    artifact_id = existing ? existing.fetch("artifact_id") : id("art")
    version = existing ? existing.fetch("current_version").to_i + 1 : 1
    version_id = id("av")
    rel_dir = File.join("artifacts", stage_id)
    file_name = "#{safe_slug(name)}-v#{version}.md"
    rel_path = File.join(rel_dir, file_name)
    abs_path = File.join(project_dir(project_id), rel_path)
    FileUtils.mkdir_p(File.dirname(abs_path))
    file_body = artifact_markdown(
      project_id: project_id,
      artifact_id: artifact_id,
      stage_id: stage_id,
      sop_id: sop_id,
      status: status,
      version: version,
      title: name,
      body: body
    )
    File.write(abs_path, file_body)
    hash = Digest::SHA256.file(abs_path).hexdigest

    if existing
      exec_sql(<<~SQL)
        UPDATE artifacts
        SET stage_id = #{q(stage_id)},
            sop_id = #{q(sop_id)},
            artifact_type = #{q(artifact_type)},
            current_version = #{version},
            status = #{q(status)},
            path = #{q(rel_path)},
            summary = #{q(summarize(body))},
            updated_at = #{q(now)}
        WHERE artifact_id = #{q(artifact_id)};
      SQL
    else
      exec_sql(<<~SQL)
        INSERT INTO artifacts
          (artifact_id, project_id, stage_id, sop_id, name, artifact_type, current_version, status, path, summary, created_at, updated_at)
        VALUES
          (#{q(artifact_id)}, #{q(project_id)}, #{q(stage_id)}, #{q(sop_id)}, #{q(name)}, #{q(artifact_type)}, #{version}, #{q(status)}, #{q(rel_path)}, #{q(summarize(body))}, #{q(now)}, #{q(now)});
      SQL
    end

    exec_sql(<<~SQL)
      INSERT INTO artifact_versions
        (version_id, artifact_id, project_id, version, status, path, content_hash, source_ref, created_at)
      VALUES
        (#{q(version_id)}, #{q(artifact_id)}, #{q(project_id)}, #{version}, #{q(status)}, #{q(rel_path)}, #{q(hash)}, #{q(source_ref)}, #{q(now)});
    SQL
    upsert_fts(project_id, "artifact", artifact_id, name, body, rel_path)
    record_event(project_id, "artifact_saved", { artifact_id: artifact_id, version: version, path: rel_path })
    refresh_all_ledgers(project_id)
    payload = { artifact_id: artifact_id, version: version, path: abs_path, relative_path: rel_path }
    puts_json(payload) if emit
    payload
  end

  def write_decision(project_id:, title:, decision:, stage_id: "", artifact_id: "", rationale: "", impact: "", verification: "", source_ref: "", status: "confirmed", emit: true)
    ensure_project!(project_id)
    now = timestamp
    decision_id = id("dec")
    exec_sql(<<~SQL)
      INSERT INTO decisions
        (decision_id, project_id, stage_id, artifact_id, title, decision, rationale, impact, verification, source_ref, status, created_at)
      VALUES
        (#{q(decision_id)}, #{q(project_id)}, #{q(stage_id)}, #{q(artifact_id)}, #{q(title)}, #{q(decision)}, #{q(rationale)}, #{q(impact)}, #{q(verification)}, #{q(source_ref)}, #{q(status)}, #{q(now)});
    SQL
    upsert_fts(project_id, "decision", decision_id, title, [decision, rationale, impact, verification].join("\n"), source_ref)
    record_event(project_id, "decision_written", { decision_id: decision_id, title: title })
    refresh_all_ledgers(project_id)
    puts_json(decision_id: decision_id) if emit
    { decision_id: decision_id }
  end

  def write_review_item(project_id:, comment:, session_id: "", role_key: "", reviewer_name: "", artifact_id: "", stage_id: "", artifact_ref: "", conclusion: "advice_only", priority: "should_fix", evidence_level: "from_artifact", user_decision: "", recommendation: "", status: "open", source_ref: "", emit: true)
    ensure_project!(project_id)
    now = timestamp
    review_item_id = id("ri")
    resolved_reviewer_name = reviewer_name.to_s.empty? && !role_key.to_s.empty? ? persona_display_name(role_key) : reviewer_name
    exec_sql(<<~SQL)
      INSERT INTO review_items
        (review_item_id, project_id, session_id, artifact_id, stage_id, role_key, reviewer_name, artifact_ref, conclusion, priority, evidence_level, user_decision, comment, recommendation, status, source_ref, created_at, updated_at)
      VALUES
        (#{q(review_item_id)}, #{q(project_id)}, #{q(session_id)}, #{q(artifact_id)}, #{q(stage_id)}, #{q(role_key)}, #{q(resolved_reviewer_name)}, #{q(artifact_ref)}, #{q(conclusion)}, #{q(priority)}, #{q(evidence_level)}, #{q(user_decision)}, #{q(comment)}, #{q(recommendation)}, #{q(status)}, #{q(source_ref)}, #{q(now)}, #{q(now)});
    SQL
    upsert_fts(project_id, "review_item", review_item_id, "#{role_key} review", [comment, recommendation].join("\n"), source_ref)
    record_event(project_id, "review_item_written", { review_item_id: review_item_id, role_key: role_key, status: status })
    refresh_all_ledgers(project_id)
    payload = { review_item_id: review_item_id }
    puts_json(payload) if emit
    payload
  end

  def open_review_session(project_id:, stage_id:, artifact_id:, artifact_version:, required_roles:, triggered_roles: [], status: "review_open", emit: true)
    ensure_project!(project_id)
    now = timestamp
    session_id = id("rs")
    rel_path = File.join("review-sessions", "#{session_id}.md")
    abs_path = File.join(project_dir(project_id), rel_path)
    FileUtils.mkdir_p(File.dirname(abs_path))
    session_body = review_session_markdown(
      session_id: session_id,
      project_id: project_id,
      stage_id: stage_id,
      artifact_id: artifact_id,
      artifact_version: artifact_version,
      status: status,
      required_roles: required_roles,
      triggered_roles: triggered_roles
    )
    File.write(abs_path, session_body)
    exec_sql(<<~SQL)
      INSERT INTO review_sessions
        (session_id, project_id, stage_id, artifact_id, artifact_version, status, required_roles, triggered_roles, decision_owner, path, created_at, updated_at)
      VALUES
        (#{q(session_id)}, #{q(project_id)}, #{q(stage_id)}, #{q(artifact_id)}, #{artifact_version.to_i}, #{q(status)}, #{q(required_roles.join(","))}, #{q(triggered_roles.join(","))}, 'user', #{q(rel_path)}, #{q(now)}, #{q(now)});
    SQL
    record_event(project_id, "review_session_opened", { session_id: session_id, stage_id: stage_id, artifact_id: artifact_id, artifact_version: artifact_version, roles: required_roles })
    payload = { session_id: session_id, path: abs_path, relative_path: rel_path }
    puts_json(payload) if emit
    payload
  end

  def write_raw_review_record(project_id:, session_id:, role_key:, artifact_id:, context_packet_id:, invocation_id:, conclusion: "advice_only", raw_review:, emit: true)
    ensure_project!(project_id)
    now = timestamp
    record_id = id("rr")
    rel_path = File.join("raw-review-records", session_id, "#{safe_file_stem(role_key)}.md")
    abs_path = File.join(project_dir(project_id), rel_path)
    FileUtils.mkdir_p(File.dirname(abs_path))
    record_body = raw_review_markdown(
      record_id: record_id,
      session_id: session_id,
      project_id: project_id,
      role_key: role_key,
      artifact_id: artifact_id,
      context_packet_id: context_packet_id,
      invocation_id: invocation_id,
      conclusion: conclusion,
      raw_review: raw_review
    )
    File.write(abs_path, record_body)
    exec_sql(<<~SQL)
      INSERT INTO raw_review_records
        (record_id, session_id, project_id, role_key, artifact_id, context_packet_id, invocation_id, conclusion, raw_review, path, created_at)
      VALUES
        (#{q(record_id)}, #{q(session_id)}, #{q(project_id)}, #{q(role_key)}, #{q(artifact_id)}, #{q(context_packet_id)}, #{q(invocation_id)}, #{q(conclusion)}, #{q(raw_review)}, #{q(rel_path)}, #{q(now)});
    SQL
    upsert_fts(project_id, "raw_review_record", record_id, "#{role_key} raw review", raw_review, rel_path)
    record_event(project_id, "raw_review_record_written", { record_id: record_id, session_id: session_id, role_key: role_key })
    payload = { record_id: record_id, path: abs_path, relative_path: rel_path }
    puts_json(payload) if emit
    payload
  end

  def write_agent_memory(project_id:, role_key:, summary:, source_ref: "", confidence: "confirmed")
    ensure_project!(project_id)
    now = timestamp
    memory_id = id("mem")
    delta_id = id("md")
    exec_sql(<<~SQL)
      INSERT INTO agent_memories
        (memory_id, project_id, role_key, summary, source_ref, confidence, status, created_at, updated_at)
      VALUES
        (#{q(memory_id)}, #{q(project_id)}, #{q(role_key)}, #{q(summary)}, #{q(source_ref)}, #{q(confidence)}, 'active', #{q(now)}, #{q(now)});
      INSERT INTO memory_deltas
        (delta_id, project_id, target_scope, target_path, role_key, source_ref, confidence, summary, status, created_at)
      VALUES
        (#{q(delta_id)}, #{q(project_id)}, 'project', #{q("agent-memory/#{role_key}.md")}, #{q(role_key)}, #{q(source_ref)}, #{q(confidence)}, #{q(summary)}, 'applied', #{q(now)});
    SQL
    write_agent_memory_file(project_id, role_key)
    record_event(project_id, "agent_memory_written", { memory_id: memory_id, role_key: role_key })
    puts_json(memory_id: memory_id, delta_id: delta_id)
  end

  def build_context_packet(project_id:, role_key:, stage_id: "", artifact_id: "", review_question: "", token_budget: 2000, emit: true)
    ensure_project!(project_id)
    now = timestamp
    packet_id = id("ctx")
    artifact = artifact_id.empty? ? latest_artifact(project_id) : query_one("SELECT * FROM artifacts WHERE project_id = #{q(project_id)} AND artifact_id = #{q(artifact_id)};")
    decisions = query("SELECT title, decision, rationale, source_ref FROM decisions WHERE project_id = #{q(project_id)} ORDER BY created_at DESC LIMIT 5;")
    review_items = query("SELECT role_key, comment, recommendation, status, source_ref FROM review_items WHERE project_id = #{q(project_id)} AND status IN ('open', 'deferred') ORDER BY created_at DESC LIMIT 5;")
    risks = query("SELECT title, description, severity, mitigation, source_ref FROM risks WHERE project_id = #{q(project_id)} AND status = 'open' ORDER BY created_at DESC LIMIT 5;")
    memories = query("SELECT summary, source_ref, confidence FROM agent_memories WHERE project_id = #{q(project_id)} AND role_key = #{q(role_key)} AND status = 'active' ORDER BY created_at DESC LIMIT 5;")
    rel_path = File.join("context-packets", "#{packet_id}.yaml")
    abs_path = File.join(project_dir(project_id), rel_path)
    FileUtils.mkdir_p(File.dirname(abs_path))
    packet = {
      "schema_version" => "0.1",
      "packet_kind" => "agent_context_packet",
      "packet_id" => packet_id,
      "project_id" => project_id,
      "stage_id" => stage_id.empty? && artifact ? artifact["stage_id"] : stage_id,
      "invocation" => {
        "real_invocation_required" => true,
        "real_invocation_performed" => false,
        "runtime_agent_id" => "",
        "simulation_label_required_if_not_called" => true
      },
      "artifact" => artifact ? {
        "artifact_id" => artifact["artifact_id"],
        "name" => artifact["name"],
        "type" => artifact["artifact_type"],
        "version" => artifact["current_version"],
        "status" => artifact["status"],
        "path" => artifact["path"],
        "summary" => artifact["summary"]
      } : {},
      "review" => {
        "role_key" => role_key,
        "review_question" => review_question,
        "expected_decision" => "pass | conditional_pass | block | advice_only"
      },
      "context" => {
        "known_decisions" => decisions,
        "open_review_items" => review_items,
        "open_risks" => risks
      },
      "memory_snapshot" => {
        "project_role_memory" => {
          "exists" => !memories.empty?,
          "recent" => memories
        },
        "memory_sources" => memories.map { |memory| memory["source_ref"] }.reject(&:empty?)
      },
      "token_budget" => token_budget,
      "created_at" => now
    }
    File.write(abs_path, packet.to_yaml)
    exec_sql(<<~SQL)
      INSERT INTO context_packets
        (packet_id, project_id, role_key, stage_id, artifact_id, path, token_budget, created_at)
      VALUES
        (#{q(packet_id)}, #{q(project_id)}, #{q(role_key)}, #{q(packet["stage_id"])}, #{q(artifact ? artifact["artifact_id"] : "")}, #{q(rel_path)}, #{token_budget.to_i}, #{q(now)});
    SQL
    record_event(project_id, "context_packet_built", { packet_id: packet_id, role_key: role_key })
    record_event(
      project_id,
      "memory_snapshot_built",
      {
        packet_id: packet_id,
        role_key: role_key,
        role_memory_exists: !memories.empty?,
        memory_sources: packet["memory_snapshot"]["memory_sources"]
      }
    )
    payload = { packet_id: packet_id, path: abs_path, relative_path: rel_path }
    puts_json(payload) if emit
    payload
  end

  def record_invocation(project_id:, role_key:, role_title: "", display_name: "", session_id: "", stage_id: "", artifact_id: "", trigger_reason: "", runtime_agent_id: "", runtime_nickname: "", context_packet_id: "", real: false, invocation_status: "", timeout_seconds: 0, required_for_gate: false, result: "", emit: true)
    ensure_project!(project_id)
    now = timestamp
    invocation_id = id("inv")
    resolved_role_title = role_title.to_s.empty? ? persona_role_title(role_key) : role_title
    resolved_display_name = display_name.to_s.empty? ? persona_display_name(role_key) : display_name
    resolved_invocation_status = invocation_status.to_s.empty? ? "completed" : invocation_status.to_s
    exec_sql(<<~SQL)
      INSERT INTO agent_invocations
        (invocation_id, project_id, role_key, role_title, display_name, session_id, stage_id, artifact_id, trigger_reason, runtime_agent_id, runtime_nickname, context_packet_id, real_invocation_performed, simulation_label_used, invocation_status, timeout_seconds, required_for_gate, result, created_at)
      VALUES
        (#{q(invocation_id)}, #{q(project_id)}, #{q(role_key)}, #{q(resolved_role_title)}, #{q(resolved_display_name)}, #{q(session_id)}, #{q(stage_id)}, #{q(artifact_id)}, #{q(trigger_reason)}, #{q(runtime_agent_id)}, #{q(runtime_nickname)}, #{q(context_packet_id)}, #{real ? 1 : 0}, #{real ? 0 : 1}, #{q(resolved_invocation_status)}, #{timeout_seconds.to_i}, #{required_for_gate ? 1 : 0}, #{q(result)}, #{q(now)});
    SQL
    record_event(project_id, "agent_invocation_recorded", { invocation_id: invocation_id, role_key: role_key, role_title: resolved_role_title, display_name: resolved_display_name, session_id: session_id, runtime_nickname: runtime_nickname, real: real, invocation_status: resolved_invocation_status })
    record_event(
      project_id,
      "agent_summoned",
      {
        invocation_id: invocation_id,
        role_key: role_key,
        role_title: resolved_role_title,
        display_name: resolved_display_name,
        session_id: session_id,
        stage_id: stage_id,
        artifact_id: artifact_id,
        trigger_reason: trigger_reason,
        runtime_agent_id: runtime_agent_id,
        runtime_nickname: runtime_nickname,
        real_invocation_performed: real,
        simulation_label_used: !real,
        invocation_status: resolved_invocation_status,
        timeout_seconds: timeout_seconds.to_i,
        required_for_gate: required_for_gate,
        context_packet_id: context_packet_id
      }
    )
    if resolved_invocation_status == "timeout"
      update_review_session_status(project_id, session_id, "blocked_by_timeout") if required_for_gate && !session_id.to_s.empty?
      record_event(
        project_id,
        "agent_invocation_timeout",
        {
          invocation_id: invocation_id,
          session_id: session_id,
          role_key: role_key,
          display_name: resolved_display_name,
          stage_id: stage_id,
          artifact_id: artifact_id,
          timeout_seconds: timeout_seconds.to_i,
          required_for_gate: required_for_gate
        }
      )
    end
    payload = {
      invocation_id: invocation_id,
      role_key: role_key,
      role_title: resolved_role_title,
      display_name: resolved_display_name,
      runtime_agent_id: runtime_agent_id,
      runtime_nickname: runtime_nickname,
      invocation_status: resolved_invocation_status
    }
    puts_json(payload) if emit
    payload
  end

  def route_intent(user_input:, project_id: "", emit: true)
    router = SemanticStageRouter.new(prompt_eval_path: File.expand_path("../tests/prompt-eval-cases.yaml", __dir__))
    decision = router.route(user_input)
    if !project_id.to_s.empty?
      ensure_project!(project_id)
      record_event(project_id, "stage_route_decision", decision.merge("user_input" => user_input))
    end
    puts_json(decision) if emit
    decision
  end

  def record_review_decision(project_id:, session_id:, action:, item_ids: "", user_confirmed: false, notes: "", emit: true)
    ensure_project!(project_id)
    session = query_one("SELECT * FROM review_sessions WHERE project_id = #{q(project_id)} AND session_id = #{q(session_id)};")
    raise "review session not found: #{session_id}" unless session

    now = timestamp
    decision_id = id("rdec")
    ids = split_roles(item_ids)
    result = "needs_user_confirmation"

    if user_confirmed
      case action
      when "accept"
        update_review_items(project_id, ids, "accepted", "accepted") unless ids.empty?
        result = "revision_needed"
        update_review_session_status(project_id, session_id, "revision_needed")
      when "reject"
        update_review_items(project_id, ids, "rejected", "rejected") unless ids.empty?
        result = "decision_logged"
        update_review_session_status(project_id, session_id, "awaiting_user_decision")
      when "defer"
        update_review_items(project_id, ids, "deferred", "deferred") unless ids.empty?
        result = "deferred"
        update_review_session_status(project_id, session_id, "awaiting_user_decision")
      when "needs_evidence"
        update_review_items(project_id, ids, "needs_evidence", "needs_evidence") unless ids.empty?
        result = "evidence_needed"
        update_review_session_status(project_id, session_id, "evidence_needed")
      when "close"
        blockers = query_value("SELECT COUNT(*) AS count FROM review_items WHERE project_id = #{q(project_id)} AND session_id = #{q(session_id)} AND status = 'open' AND priority IN ('must_fix', 'block');").to_i
        if blockers.positive?
          result = "blocked_by_open_must_fix"
          update_review_session_status(project_id, session_id, "awaiting_user_decision")
        else
          result = "closed_by_user"
          update_review_session_status(project_id, session_id, "closed_by_user")
        end
      else
        raise "unknown review decision action: #{action}"
      end
    end

    exec_sql(<<~SQL)
      INSERT INTO review_decisions
        (decision_id, project_id, session_id, action, item_ids, user_confirmed, notes, result, created_at)
      VALUES
        (#{q(decision_id)}, #{q(project_id)}, #{q(session_id)}, #{q(action)}, #{q(item_ids)}, #{user_confirmed ? 1 : 0}, #{q(notes)}, #{q(result)}, #{q(now)});
    SQL
    write_decision(
      project_id: project_id,
      title: "Review decision #{action}",
      decision: result,
      stage_id: session["stage_id"].to_s,
      artifact_id: session["artifact_id"].to_s,
      rationale: notes,
      source_ref: "review-session:#{session_id}",
      status: user_confirmed ? "confirmed" : "pending_confirmation",
      emit: false
    )
    record_event(project_id, "review_decision_recorded", { session_id: session_id, action: action, item_ids: ids, user_confirmed: user_confirmed, result: result })
    refresh_all_ledgers(project_id)
    payload = { decision_id: decision_id, session_id: session_id, action: action, user_confirmed: user_confirmed, result: result, status: review_session_status(project_id, session_id) }
    puts_json(payload) if emit
    payload
  end

  def export_obsidian(project_id:, output_dir:)
    ensure_project!(project_id)
    project = project(project_id)
    root = File.expand_path(output_dir)
    project_root = File.join(root, "Projects", safe_slug(project.fetch("name")))
    flow_dirs = FLOW_DIRS.values.uniq
    (flow_dirs + ["_项目账本", File.join("_项目账本", "review-sessions"), File.join("_项目账本", "raw-review-records"), "_团队记忆", "_导出", File.join("_导出", "word"), File.join("_导出", "pdf"), File.join("_导出", "release-notes")]).each do |dir|
      FileUtils.mkdir_p(File.join(project_root, dir))
    end
    write_obsidian_home(project_id, project_root)
    export_artifacts(project_id, project_root)
    export_ledgers(project_id, project_root)
    export_team_memory(project_id, project_root)
    record_event(project_id, "obsidian_exported", { output_dir: project_root })
    puts_json(project_id: project_id, obsidian_vault: root, project_path: project_root)
  end

  def record_turn(project_id:, stage_id:, macro_stage: "", sop_id: "", user_input: "", route_confidence: "smoke", primary_skill:, fallback_skill: "", skill_status: "completed", artifact_name:, artifact_content_file: nil, artifact_content: nil, artifact_status: "draft", gate_status: "conditional_pass", gate_result: "", review_roles: "", source_ref: "")
    ensure_project!(project_id)
    now = timestamp
    sop_run_id = id("sop")
    sop_id = stage_id if sop_id.empty?
    macro_stage = infer_macro_stage(stage_id) if macro_stage.empty?

    exec_sql(<<~SQL)
      UPDATE projects
      SET current_stage_id = #{q(stage_id)},
          current_macro_stage = #{q(macro_stage)},
          updated_at = #{q(now)}
      WHERE project_id = #{q(project_id)};

      INSERT INTO stages
        (project_id, stage_id, macro_stage, status, gate_status, started_at, completed_at)
      VALUES
        (#{q(project_id)}, #{q(stage_id)}, #{q(macro_stage)}, 'completed', #{q(gate_status)}, #{q(now)}, #{q(now)});

      INSERT INTO sop_runs
        (run_id, project_id, stage_id, sop_id, user_input, route_confidence, result, created_at)
      VALUES
        (#{q(sop_run_id)}, #{q(project_id)}, #{q(stage_id)}, #{q(sop_id)}, #{q(user_input)}, #{q(route_confidence)}, #{q(gate_result)}, #{q(now)});
    SQL
    record_event(
      project_id,
      "stage_detected",
      {
        sop_run_id: sop_run_id,
        stage_id: stage_id,
        macro_stage: macro_stage,
        sop_id: sop_id,
        route_confidence: route_confidence
      }
    )

    artifact_body = artifact_content || (artifact_content_file ? File.read(artifact_content_file) : "")
    if artifact_body.strip.empty?
      artifact_body = <<~MARKDOWN
        ## Runtime Adapter Artifact

        - Stage: `#{stage_id}`
        - SOP: `#{sop_id}`
        - Primary skill: `#{primary_skill}`
        - Fallback skill: `#{fallback_skill}`
        - Gate: `#{gate_status}`

        User input:

        > #{user_input}
      MARKDOWN
    end

    artifact = save_artifact(
      project_id: project_id,
      name: artifact_name,
      stage_id: stage_id,
      sop_id: sop_id,
      artifact_type: "markdown",
      status: artifact_status,
      content: artifact_body,
      source_ref: source_ref.empty? ? "runtime-adapter:#{sop_run_id}" : source_ref,
      emit: false
    )

    skill_run_id = id("skill")
    exec_sql(<<~SQL)
      INSERT INTO skill_runs
        (run_id, project_id, stage_id, skill_name, fallback_skill_name, status, output_ref, created_at)
      VALUES
        (#{q(skill_run_id)}, #{q(project_id)}, #{q(stage_id)}, #{q(primary_skill)}, #{q(fallback_skill)}, #{q(skill_status)}, #{q(artifact[:artifact_id])}, #{q(now)});
    SQL
    record_event(
      project_id,
      "skill_selected",
      {
        skill_run_id: skill_run_id,
        stage_id: stage_id,
        selected_skill: primary_skill,
        fallback_skill: fallback_skill,
        status: skill_status,
        output_ref: artifact[:artifact_id]
      }
    )

    role_outputs = []
    requested_roles = split_roles(review_roles)
    roles = requested_roles.empty? ? ["Coach"] : requested_roles
    review_session = nil
    unless requested_roles.empty?
      review_session = open_review_session(
        project_id: project_id,
        stage_id: stage_id,
        artifact_id: artifact[:artifact_id],
        artifact_version: artifact[:version],
        required_roles: roles,
        emit: false
      )
    end
    roles.each do |role_key|
      display_name = persona_display_name(role_key)
      packet = build_context_packet(
        project_id: project_id,
        role_key: role_key,
        stage_id: stage_id,
        artifact_id: artifact[:artifact_id],
        review_question: "Review #{artifact_name} for #{stage_id}.",
        token_budget: 1200,
        emit: false
      )
      invocation = record_invocation(
        project_id: project_id,
        role_key: role_key,
        display_name: display_name,
        session_id: review_session ? review_session[:session_id] : "",
        stage_id: stage_id,
        artifact_id: artifact[:artifact_id],
        trigger_reason: "record-turn review_roles",
        runtime_agent_id: "",
        runtime_nickname: "",
        context_packet_id: packet[:packet_id],
        real: false,
        invocation_status: "completed",
        required_for_gate: requested_roles.include?(role_key),
        result: "runtime_adapter_recorded_context",
        emit: false
      )
      review_item = write_review_item(
        project_id: project_id,
        session_id: review_session ? review_session[:session_id] : "",
        artifact_id: artifact[:artifact_id],
        stage_id: stage_id,
        role_key: role_key,
        reviewer_name: display_name,
        artifact_ref: "#{artifact_name} v#{artifact[:version]}",
        conclusion: "advice_only",
        priority: "should_fix",
        evidence_level: "from_artifact",
        comment: "Runtime adapter recorded #{display_name} (#{role_key}) review context for #{stage_id}.",
        recommendation: "Use a real sub-agent invocation when the host environment provides one; otherwise keep the simulated-perspective label.",
        status: "open",
        source_ref: "runtime-adapter:#{sop_run_id}",
        emit: false
      )
      raw_review = nil
      if review_session
        raw_review = write_raw_review_record(
          project_id: project_id,
          session_id: review_session[:session_id],
          role_key: role_key,
          artifact_id: artifact[:artifact_id],
          context_packet_id: packet[:packet_id],
          invocation_id: invocation[:invocation_id],
          conclusion: "advice_only",
          raw_review: "Runtime adapter recorded #{display_name} (#{role_key}) independent review for #{artifact_name}. Host runtimes with real sub-agents should replace this with the actual raw review output.",
          emit: false
        )
      end
      role_outputs << {
        role_key: role_key,
        packet_id: packet[:packet_id],
        invocation_id: invocation[:invocation_id],
        review_item_id: review_item[:review_item_id],
        raw_review_record_id: raw_review ? raw_review[:record_id] : ""
      }
    end
    update_review_session_status(project_id, review_session[:session_id], "awaiting_user_decision") if review_session

    record_event(
      project_id,
      "turn_recorded",
      {
        sop_run_id: sop_run_id,
        skill_run_id: skill_run_id,
        stage_id: stage_id,
        sop_id: sop_id,
        primary_skill: primary_skill,
        fallback_skill: fallback_skill,
        artifact_id: artifact[:artifact_id],
        gate_status: gate_status
      }
    )
    record_event(
      project_id,
      "stage_gate_decision",
      {
        sop_run_id: sop_run_id,
        stage_id: stage_id,
        gate_status: gate_status,
        gate_result: gate_result,
        artifact_id: artifact[:artifact_id]
      }
    )
    refresh_all_ledgers(project_id)
    puts_json(
      project_id: project_id,
      sop_run_id: sop_run_id,
      skill_run_id: skill_run_id,
      artifact_id: artifact[:artifact_id],
      review_session_id: review_session ? review_session[:session_id] : "",
      stage_id: stage_id,
      gate_status: gate_status,
      roles: role_outputs
    )
  end

  private

  def apply_schema
    schema_path = File.expand_path("db/schema.sql", __dir__)
    exec_sql(File.read(schema_path))
    migrate_schema!
  end

  def migrate_schema!
    ensure_column("agent_invocations", "role_title", "TEXT DEFAULT ''")
    ensure_column("agent_invocations", "runtime_nickname", "TEXT DEFAULT ''")
    ensure_column("agent_invocations", "session_id", "TEXT DEFAULT ''")
    ensure_column("agent_invocations", "stage_id", "TEXT DEFAULT ''")
    ensure_column("agent_invocations", "artifact_id", "TEXT DEFAULT ''")
    ensure_column("agent_invocations", "trigger_reason", "TEXT DEFAULT ''")
    ensure_column("agent_invocations", "invocation_status", "TEXT DEFAULT 'completed'")
    ensure_column("agent_invocations", "timeout_seconds", "INTEGER DEFAULT 0")
    ensure_column("agent_invocations", "required_for_gate", "INTEGER DEFAULT 0")
    ensure_column("review_items", "session_id", "TEXT DEFAULT ''")
    ensure_column("review_items", "artifact_ref", "TEXT DEFAULT ''")
    ensure_column("review_items", "conclusion", "TEXT DEFAULT 'advice_only'")
    ensure_column("review_items", "priority", "TEXT DEFAULT 'should_fix'")
    ensure_column("review_items", "evidence_level", "TEXT DEFAULT 'from_artifact'")
    ensure_column("review_items", "user_decision", "TEXT DEFAULT ''")
  end

  def ensure_column(table, column, definition)
    columns = query("PRAGMA table_info(#{table});").map { |row| row.fetch("name") }
    return if columns.include?(column)

    exec_sql("ALTER TABLE #{table} ADD COLUMN #{column} #{definition};")
  end

  def sqlite_args
    ["sqlite3", "-cmd", ".timeout 5000", "-cmd", "PRAGMA foreign_keys = ON;", @db_path]
  end

  def exec_sql(sql)
    stdout, stderr, status = Open3.capture3(*sqlite_args, stdin_data: sql)
    raise "sqlite failed: #{stderr.strip}\n#{sql}" unless status.success?
    stdout
  end

  def query(sql)
    stdout, stderr, status = Open3.capture3("sqlite3", "-cmd", ".timeout 5000", "-cmd", "PRAGMA foreign_keys = ON;", "-json", @db_path, sql)
    raise "sqlite query failed: #{stderr.strip}\n#{sql}" unless status.success?
    stdout.strip.empty? ? [] : JSON.parse(stdout)
  end

  def query_one(sql)
    query(sql).first
  end

  def query_value(sql, key = "count")
    query(sql).first&.fetch(key, nil)
  end

  def q(value)
    return "NULL" if value.nil?
    "'#{value.to_s.gsub("'", "''")}'"
  end

  def id(prefix)
    "#{prefix}_#{Time.now.utc.strftime("%Y%m%d%H%M%S")}_#{SecureRandom.hex(4)}"
  end

  def timestamp
    Time.now.utc.iso8601
  end

  def project_dir(project_id)
    File.join(@workspace, "memory", "projects", project_id)
  end

  def project(project_id)
    row = query_one("SELECT * FROM projects WHERE project_id = #{q(project_id)};")
    raise "project not found: #{project_id}" unless row
    row
  end

  def ensure_project!(project_id)
    project(project_id)
  end

  def create_project_workspace(project_id, name)
    root = project_dir(project_id)
    dirs = %w[artifacts context-packets review-sessions raw-review-records agent-memory checkpoints exports]
    dirs.each { |dir| FileUtils.mkdir_p(File.join(root, dir)) }
    write_if_missing(File.join(root, "project-home.md"), "# #{name}\n\n- Project ID: `#{project_id}`\n- Source of truth: Product Crew OS Runtime\n")
    write_if_missing(File.join(root, "timeline.md"), "# Timeline\n")
    write_if_missing(File.join(root, "decision-log.md"), "# Decision Log\n")
    write_if_missing(File.join(root, "source-ledger.md"), "# Source Ledger\n")
    write_if_missing(File.join(root, "next-actions.md"), "# Next Actions\n")
    write_if_missing(File.join(root, "risk-log.md"), "# Risk Log\n")
    write_if_missing(File.join(root, "conflict-matrix.md"), "# Conflict Matrix\n")
    write_if_missing(File.join(root, "open-questions.md"), "# Open Questions\n")
    write_if_missing(File.join(root, "artifact-diff.md"), "# Artifact Diff\n")
    write_if_missing(File.join(root, "event-log.jsonl"), "")
    write_if_missing(File.join(root, "review-items.yaml"), { "review_items" => [] }.to_yaml)
    write_if_missing(File.join(root, "artifact-index.yaml"), { "artifacts" => [] }.to_yaml)
    write_if_missing(File.join(root, "exports", "export-manifest.yaml"), { "exports" => [] }.to_yaml)
  end

  def write_if_missing(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content) unless File.exist?(path)
  end

  def write_project_state(project_id)
    project = project(project_id)
    state = {
      "schema_version" => "1.0",
      "project_id" => project_id,
      "project" => project["name"],
      "current_stage_id" => project["current_stage_id"],
      "current_macro_stage" => project["current_macro_stage"],
      "status" => project["status"],
      "updated_at" => project["updated_at"],
      "database" => @db_path,
      "workspace_path" => project["workspace_path"]
    }
    File.write(File.join(project_dir(project_id), "project-state.json"), JSON.pretty_generate(state))
  end

  def refresh_all_ledgers(project_id)
    write_project_state(project_id)
    refresh_artifact_index(project_id)
    refresh_decision_log(project_id)
    refresh_review_items(project_id)
    refresh_timeline(project_id)
    refresh_source_ledger(project_id)
  end

  def refresh_artifact_index(project_id)
    artifacts = query("SELECT artifact_id, name, artifact_type, stage_id, sop_id, current_version, status, path, summary, created_at, updated_at FROM artifacts WHERE project_id = #{q(project_id)} ORDER BY updated_at DESC;")
    File.write(File.join(project_dir(project_id), "artifact-index.yaml"), { "schema_version" => "1.0", "project_id" => project_id, "artifacts" => artifacts }.to_yaml)
  end

  def refresh_decision_log(project_id)
    decisions = query("SELECT * FROM decisions WHERE project_id = #{q(project_id)} ORDER BY created_at DESC;")
    lines = ["# Decision Log", ""]
    decisions.each do |decision|
      lines << "## #{decision["title"]}"
      lines << ""
      lines << "- ID: `#{decision["decision_id"]}`"
      lines << "- Status: `#{decision["status"]}`"
      lines << "- Stage: `#{decision["stage_id"]}`"
      lines << "- Source: `#{decision["source_ref"]}`"
      lines << "- Decision: #{decision["decision"]}"
      lines << "- Rationale: #{decision["rationale"]}"
      lines << "- Impact: #{decision["impact"]}"
      lines << "- Verification: #{decision["verification"]}"
      lines << ""
    end
    File.write(File.join(project_dir(project_id), "decision-log.md"), lines.join("\n"))
  end

  def refresh_review_items(project_id)
    items = query("SELECT * FROM review_items WHERE project_id = #{q(project_id)} ORDER BY created_at DESC;")
    File.write(File.join(project_dir(project_id), "review-items.yaml"), { "schema_version" => "1.0", "project_id" => project_id, "review_items" => items }.to_yaml)
  end

  def refresh_timeline(project_id)
    events = query("SELECT event_type, payload_json, created_at FROM events WHERE project_id = #{q(project_id)} ORDER BY created_at ASC;")
    lines = ["# Timeline", ""]
    events.each do |event|
      lines << "- #{event["created_at"]} `#{event["event_type"]}` #{event["payload_json"]}"
    end
    File.write(File.join(project_dir(project_id), "timeline.md"), lines.join("\n"))
  end

  def refresh_source_ledger(project_id)
    artifact_sources = query("SELECT version_id AS id, source_ref, path, created_at FROM artifact_versions WHERE project_id = #{q(project_id)} AND source_ref != '' ORDER BY created_at DESC;")
    decision_sources = query("SELECT decision_id AS id, source_ref, title AS path, created_at FROM decisions WHERE project_id = #{q(project_id)} AND source_ref != '' ORDER BY created_at DESC;")
    lines = ["# Source Ledger", ""]
    (artifact_sources + decision_sources).each do |source|
      lines << "- #{source["created_at"]} `#{source["id"]}` source=`#{source["source_ref"]}` ref=`#{source["path"]}`"
    end
    File.write(File.join(project_dir(project_id), "source-ledger.md"), lines.join("\n"))
  end

  def write_agent_memory_file(project_id, role_key)
    memories = query("SELECT summary, source_ref, confidence, created_at FROM agent_memories WHERE project_id = #{q(project_id)} AND role_key = #{q(role_key)} AND status = 'active' ORDER BY created_at DESC;")
    lines = ["# Agent Memory: #{role_key}", ""]
    memories.each do |memory|
      lines << "- #{memory["created_at"]} [#{memory["confidence"]}] #{memory["summary"]} (source: `#{memory["source_ref"]}`)"
    end
    File.write(File.join(project_dir(project_id), "agent-memory", "#{safe_slug(role_key)}.md"), lines.join("\n"))
  end

  def record_event(project_id, event_type, payload = {})
    now = timestamp
    event_id = id("evt")
    payload_json = JSON.generate(payload)
    exec_sql(<<~SQL)
      INSERT INTO events (event_id, project_id, event_type, payload_json, created_at)
      VALUES (#{q(event_id)}, #{q(project_id)}, #{q(event_type)}, #{q(payload_json)}, #{q(now)});
    SQL
    event_path = File.join(project_dir(project_id), "event-log.jsonl")
    FileUtils.mkdir_p(File.dirname(event_path))
    File.open(event_path, "a") do |file|
      file.puts(JSON.generate("event_id" => event_id, "project_id" => project_id, "event_type" => event_type, "payload" => payload, "created_at" => now))
    end
  end

  def upsert_fts(project_id, doc_type, doc_id, title, body, source_ref)
    exec_sql(<<~SQL)
      DELETE FROM fts_documents WHERE project_id = #{q(project_id)} AND doc_type = #{q(doc_type)} AND doc_id = #{q(doc_id)};
      INSERT INTO fts_documents (project_id, doc_type, doc_id, title, body, source_ref)
      VALUES (#{q(project_id)}, #{q(doc_type)}, #{q(doc_id)}, #{q(title)}, #{q(body)}, #{q(source_ref)});
    SQL
  end

  def latest_artifact(project_id)
    query_one("SELECT * FROM artifacts WHERE project_id = #{q(project_id)} ORDER BY updated_at DESC LIMIT 1;")
  end

  def safe_slug(value)
    slug = value.to_s.strip.downcase.gsub(/[^0-9a-zA-Z\p{Han}_-]+/u, "-").gsub(/-+/, "-").gsub(/^-|-$/, "")
    slug.empty? ? "untitled" : slug
  end

  def safe_file_stem(value)
    stem = value.to_s.strip.gsub(/[^0-9a-zA-Z\p{Han}_-]+/u, "-").gsub(/-+/, "-").gsub(/^-|-$/, "")
    stem.empty? ? "untitled" : stem
  end

  def split_roles(value)
    value.to_s.split(/[,\n;]/).map(&:strip).reject(&:empty?).uniq
  end

  def update_review_items(project_id, item_ids, status, user_decision)
    return if item_ids.empty?

    quoted_ids = item_ids.map { |item_id| q(item_id) }.join(",")
    exec_sql(<<~SQL)
      UPDATE review_items
      SET status = #{q(status)},
          user_decision = #{q(user_decision)},
          updated_at = #{q(timestamp)}
      WHERE project_id = #{q(project_id)}
        AND review_item_id IN (#{quoted_ids});
    SQL
  end

  def update_review_session_status(project_id, session_id, status)
    exec_sql(<<~SQL)
      UPDATE review_sessions
      SET status = #{q(status)},
          updated_at = #{q(timestamp)}
      WHERE project_id = #{q(project_id)}
        AND session_id = #{q(session_id)};
    SQL
    record_event(project_id, "review_session_status_changed", { session_id: session_id, status: status })
  end

  def review_session_status(project_id, session_id)
    query_one("SELECT status FROM review_sessions WHERE project_id = #{q(project_id)} AND session_id = #{q(session_id)};")&.fetch("status", "")
  end

  def persona_by_role_key
    @persona_by_role_key ||= begin
      config_path = File.expand_path("../config/crew-personas.yaml", __dir__)
      personas = File.exist?(config_path) ? YAML.load_file(config_path).fetch("personas", {}) : {}
      personas.values.each_with_object({}) do |persona, memo|
        role_key = persona.fetch("role_key", "").to_s
        memo[role_key] = persona unless role_key.empty?
      end
    end
  end

  def persona(role_key)
    persona_by_role_key.fetch(role_key.to_s, {})
  end

  def persona_display_name(role_key)
    persona(role_key).fetch("display_name", role_key.to_s)
  end

  def persona_role_title(role_key)
    persona(role_key).fetch("title", role_key.to_s)
  end

  def infer_macro_stage(stage_id)
    case stage_id
    when "project_intake", "request_triage", "stakeholder_map", "business_context", "existing_workflow_mapping", "evidence_inventory"
      "opportunity_discovery"
    when "research_plan", "interview_guide", "interview_synthesis", "persona_jtbd_journey"
      "user_research"
    when "problem_definition", "user_segmentation", "opportunity_tree", "assumption_mapping"
      "problem_framing"
    when "value_sizing", "prioritization", "mvp_scope", "one_page_proposal"
      "requirement_analysis"
    when "solution_exploration", "data_feasibility_precheck", "technical_feasibility_precheck", "compliance_precheck", "core_flow_diagram", "low_fi_prototype", "metrics_design", "instrumentation_plan"
      "solution_design"
    when "prd_outline", "prd_v0_draft", "pm_self_review"
      "prd_drafting"
    when "internal_product_review", "design_review", "data_review", "technical_pre_review", "formal_requirements_review"
      "cross_functional_review"
    when "task_breakdown", "acceptance_criteria", "development_tracking", "integration_qa"
      "delivery_planning"
    when "launch_readiness", "training_enablement", "grey_release_pilot"
      "launch_readiness"
    when "launch_monitoring"
      "launch_monitoring"
    else
      "post_launch_review"
    end
  end

  def summarize(body)
    body.to_s.gsub(/\s+/, " ").strip[0, 240].to_s
  end

  def artifact_markdown(project_id:, artifact_id:, stage_id:, sop_id:, status:, version:, title:, body:)
    frontmatter = {
      "project_id" => project_id,
      "artifact_id" => artifact_id,
      "stage_id" => stage_id,
      "sop_id" => sop_id,
      "status" => status,
      "version" => version,
      "source_of_truth" => "Product Crew OS Runtime",
      "last_synced_at" => timestamp
    }
    ["---", frontmatter.to_yaml.sub(/\A---\n/, "").strip, "---", "", "# #{title}", "", body].join("\n")
  end

  def review_session_markdown(session_id:, project_id:, stage_id:, artifact_id:, artifact_version:, status:, required_roles:, triggered_roles:)
    frontmatter = {
      "project_id" => project_id,
      "review_session_id" => session_id,
      "stage_id" => stage_id,
      "artifact_id" => artifact_id,
      "artifact_version" => artifact_version,
      "status" => status,
      "source_of_truth" => "Product Crew OS Runtime",
      "last_synced_at" => timestamp
    }
    lines = [
      "---",
      frontmatter.to_yaml.sub(/\A---\n/, "").strip,
      "---",
      "",
      "# Review Session #{session_id}",
      "",
      "## 评审对象",
      "",
      "- Artifact: `#{artifact_id}`",
      "- Version: `#{artifact_version}`",
      "- Stage: `#{stage_id}`",
      "- Status: `#{status}`",
      "- Decision owner: `user`",
      "",
      "## 参与角色",
      "",
      "| role_key | 角色 | 显示名 | role_type |",
      "| --- | --- | --- | --- |"
    ]
    required_roles.each { |role| lines << "| #{role} | #{persona_role_title(role)} | #{persona_display_name(role)} | required |" }
    triggered_roles.each { |role| lines << "| #{role} | #{persona_role_title(role)} | #{persona_display_name(role)} | triggered |" }
    lines += [
      "",
      "## 评审规则",
      "",
      "- 角色独立评审，不先互相看结论。",
      "- 主控只收束 must-fix、should-fix、conflict 和 open questions。",
      "- 用户决定采纳、拒绝、暂缓或要求补证据。",
      "- Artifact 修改后要写 artifact-diff，并只让相关角色复评。"
    ]
    lines.join("\n")
  end

  def raw_review_markdown(record_id:, session_id:, project_id:, role_key:, artifact_id:, context_packet_id:, invocation_id:, conclusion:, raw_review:)
    invocation = invocation_id.to_s.empty? ? nil : query_one("SELECT role_title, display_name, runtime_agent_id, runtime_nickname FROM agent_invocations WHERE invocation_id = #{q(invocation_id)};")
    role_title = invocation ? invocation["role_title"].to_s : persona_role_title(role_key)
    display_name = invocation ? invocation["display_name"].to_s : persona_display_name(role_key)
    runtime_agent_id = invocation ? invocation["runtime_agent_id"].to_s : ""
    runtime_nickname = invocation ? invocation["runtime_nickname"].to_s : ""
    frontmatter = {
      "project_id" => project_id,
      "review_record_id" => record_id,
      "review_session_id" => session_id,
      "role_key" => role_key,
      "role_title" => role_title,
      "display_name" => display_name,
      "runtime_agent_id" => runtime_agent_id,
      "runtime_nickname" => runtime_nickname,
      "runtime_nickname_policy" => "audit_only",
      "artifact_id" => artifact_id,
      "context_packet_id" => context_packet_id,
      "invocation_id" => invocation_id,
      "conclusion" => conclusion,
      "source_of_truth" => "Product Crew OS Runtime",
      "last_synced_at" => timestamp
    }
    [
      "---",
      frontmatter.to_yaml.sub(/\A---\n/, "").strip,
      "---",
      "",
      "# Raw Review: #{display_name} / #{role_key}",
      "",
      "- Role title: `#{role_title}`",
      "- Display name: `#{display_name}`",
      "- Runtime nickname: `#{runtime_nickname}` (audit only)",
      "- Review Session: `#{session_id}`",
      "- Artifact: `#{artifact_id}`",
      "- Context Packet: `#{context_packet_id}`",
      "- Invocation: `#{invocation_id}`",
      "- Conclusion: `#{conclusion}`",
      "",
      "## 原始评审记录",
      "",
      raw_review
    ].join("\n")
  end

  def write_obsidian_home(project_id, project_root)
    project = project(project_id)
    artifacts = query("SELECT artifact_id, name, stage_id, status, path FROM artifacts WHERE project_id = #{q(project_id)} ORDER BY updated_at DESC;")
    decisions = query("SELECT decision_id, title, decision FROM decisions WHERE project_id = #{q(project_id)} ORDER BY created_at DESC LIMIT 8;")
    lines = [
      "---",
      { "project_id" => project_id, "source_of_truth" => "Product Crew OS Runtime", "last_synced_at" => timestamp }.to_yaml.sub(/\A---\n/, "").strip,
      "---",
      "",
      "# #{project["name"]}",
      "",
      "## Current Stage",
      "",
      "- Stage: `#{project["current_stage_id"]}`",
      "- Status: `#{project["status"]}`",
      "",
      "## Artifacts",
      ""
    ]
    artifacts.each { |artifact| lines << "- [[#{artifact["name"]}]] `#{artifact["stage_id"]}` `#{artifact["status"]}`" }
    lines << ""
    lines << "## Recent Decisions"
    lines << ""
    decisions.each { |decision| lines << "- #{decision["title"]}: #{decision["decision"]}" }
    File.write(File.join(project_root, "00_项目首页.md"), lines.join("\n"))
  end

  def export_artifacts(project_id, project_root)
    artifacts = query("SELECT * FROM artifacts WHERE project_id = #{q(project_id)} ORDER BY updated_at DESC;")
    artifacts.each do |artifact|
      source_path = File.join(project_dir(project_id), artifact["path"])
      next unless File.exist?(source_path)
      flow_key = FLOW_DIRS.key?(artifact["stage_id"]) ? artifact["stage_id"] : infer_macro_stage(artifact["stage_id"])
      target_dir = File.join(project_root, FLOW_DIRS.fetch(flow_key, "01_机会发现"))
      FileUtils.mkdir_p(target_dir)
      FileUtils.cp(source_path, File.join(target_dir, "#{safe_slug(artifact["name"])}.md"))
    end
  end

  def export_ledgers(project_id, project_root)
    mapping = {
      "artifact-index.yaml" => "artifact-index.yaml",
      "timeline.md" => "timeline.md",
      "decision-log.md" => "decision-log.md",
      "review-items.yaml" => "review-items.yaml",
      "risk-log.md" => "risk-log.md",
      "next-actions.md" => "next-actions.md",
      "conflict-matrix.md" => "conflict-matrix.md",
      "open-questions.md" => "open-questions.md",
      "artifact-diff.md" => "artifact-diff.md",
      "source-ledger.md" => "source-ledger.md",
      "event-log.jsonl" => "event-log.jsonl"
    }
    mapping.each do |source, target|
      source_path = File.join(project_dir(project_id), source)
      FileUtils.cp(source_path, File.join(project_root, "_项目账本", target)) if File.exist?(source_path)
    end
    copy_directory(File.join(project_dir(project_id), "review-sessions"), File.join(project_root, "_项目账本", "review-sessions"))
    copy_directory(File.join(project_dir(project_id), "raw-review-records"), File.join(project_root, "_项目账本", "raw-review-records"))
  end

  def export_team_memory(project_id, project_root)
    Dir[File.join(project_dir(project_id), "agent-memory", "*.md")].each do |path|
      FileUtils.cp(path, File.join(project_root, "_团队记忆", File.basename(path)))
    end
  end

  def copy_directory(source_dir, target_dir)
    return unless Dir.exist?(source_dir)

    FileUtils.mkdir_p(target_dir)
    Dir[File.join(source_dir, "**", "*")].each do |source_path|
      next if File.directory?(source_path)

      relative = source_path.sub("#{source_dir}/", "")
      target_path = File.join(target_dir, relative)
      FileUtils.mkdir_p(File.dirname(target_path))
      FileUtils.cp(source_path, target_path)
    end
  end

  def puts_json(payload)
    puts(JSON.pretty_generate(payload))
  end
end

def parse_args(argv)
  command = argv.shift
  options = {}
  until argv.empty?
    key = argv.shift
    raise "expected --key, got #{key}" unless key&.start_with?("--")
    value = argv.shift
    raise "missing value for #{key}" if value.nil?
    options[key.sub(/\A--/, "").tr("-", "_")] = value
  end
  [command, options]
end

def require_option(options, key)
  value = options[key]
  raise "missing --#{key.tr("_", "-")}" if value.nil? || value.empty?
  value
end

command, options = parse_args(ARGV)
workspace = options["workspace"] || File.expand_path("runtime-workspace", Dir.pwd)
db = options["db"] || File.join(workspace, "product-crew-os.sqlite3")
runtime = ProductCrewRuntime.new(db_path: db, workspace: workspace)

case command
when "init-project"
  runtime.init_project(
    project_id: require_option(options, "project_id"),
    name: require_option(options, "name"),
    description: options["description"].to_s,
    owner: options["owner"].to_s
  )
when "save-artifact"
  runtime.save_artifact(
    project_id: require_option(options, "project_id"),
    name: require_option(options, "name"),
    stage_id: require_option(options, "stage_id"),
    sop_id: options["sop_id"].to_s,
    artifact_type: options["artifact_type"] || "markdown",
    status: options["status"] || "draft",
    content_file: options["content_file"],
    content: options["content"],
    source_ref: options["source_ref"].to_s
  )
when "write-decision"
  runtime.write_decision(
    project_id: require_option(options, "project_id"),
    title: require_option(options, "title"),
    decision: require_option(options, "decision"),
    stage_id: options["stage_id"].to_s,
    artifact_id: options["artifact_id"].to_s,
    rationale: options["rationale"].to_s,
    impact: options["impact"].to_s,
    verification: options["verification"].to_s,
    source_ref: options["source_ref"].to_s,
    status: options["status"] || "confirmed"
  )
when "write-review-item"
  runtime.write_review_item(
    project_id: require_option(options, "project_id"),
    comment: require_option(options, "comment"),
    session_id: options["session_id"].to_s,
    role_key: options["role_key"].to_s,
    reviewer_name: options["reviewer_name"].to_s,
    artifact_id: options["artifact_id"].to_s,
    stage_id: options["stage_id"].to_s,
    artifact_ref: options["artifact_ref"].to_s,
    conclusion: options["conclusion"] || "advice_only",
    priority: options["priority"] || "should_fix",
    evidence_level: options["evidence_level"] || "from_artifact",
    user_decision: options["user_decision"].to_s,
    recommendation: options["recommendation"].to_s,
    status: options["status"] || "open",
    source_ref: options["source_ref"].to_s
  )
when "write-agent-memory"
  runtime.write_agent_memory(
    project_id: require_option(options, "project_id"),
    role_key: require_option(options, "role_key"),
    summary: require_option(options, "summary"),
    source_ref: options["source_ref"].to_s,
    confidence: options["confidence"] || "confirmed"
  )
when "build-context-packet"
  runtime.build_context_packet(
    project_id: require_option(options, "project_id"),
    role_key: require_option(options, "role_key"),
    stage_id: options["stage_id"].to_s,
    artifact_id: options["artifact_id"].to_s,
    review_question: options["review_question"].to_s,
    token_budget: (options["token_budget"] || "2000").to_i
  )
when "record-invocation"
  runtime.record_invocation(
    project_id: require_option(options, "project_id"),
    role_key: require_option(options, "role_key"),
    role_title: options["role_title"].to_s,
    display_name: options["display_name"].to_s,
    session_id: options["session_id"].to_s,
    stage_id: options["stage_id"].to_s,
    artifact_id: options["artifact_id"].to_s,
    trigger_reason: options["trigger_reason"].to_s,
    runtime_agent_id: options["runtime_agent_id"].to_s,
    runtime_nickname: options["runtime_nickname"].to_s,
    context_packet_id: options["context_packet_id"].to_s,
    real: options["real"].to_s == "true",
    invocation_status: options["invocation_status"].to_s,
    timeout_seconds: (options["timeout_seconds"] || "0").to_i,
    required_for_gate: options["required_for_gate"].to_s == "true",
    result: options["result"].to_s
  )
when "write-raw-review-record"
  runtime.write_raw_review_record(
    project_id: require_option(options, "project_id"),
    session_id: require_option(options, "session_id"),
    role_key: require_option(options, "role_key"),
    artifact_id: options["artifact_id"].to_s,
    context_packet_id: options["context_packet_id"].to_s,
    invocation_id: options["invocation_id"].to_s,
    conclusion: options["conclusion"] || "advice_only",
    raw_review: require_option(options, "raw_review")
  )
when "route-intent"
  runtime.route_intent(
    project_id: options["project_id"].to_s,
    user_input: require_option(options, "user_input")
  )
when "record-review-decision"
  runtime.record_review_decision(
    project_id: require_option(options, "project_id"),
    session_id: require_option(options, "session_id"),
    action: require_option(options, "action"),
    item_ids: options["item_ids"].to_s,
    user_confirmed: options["user_confirmed"].to_s == "true",
    notes: options["notes"].to_s
  )
when "record-turn"
  runtime.record_turn(
    project_id: require_option(options, "project_id"),
    stage_id: require_option(options, "stage_id"),
    macro_stage: options["macro_stage"].to_s,
    sop_id: options["sop_id"].to_s,
    user_input: options["user_input"].to_s,
    route_confidence: options["route_confidence"] || "smoke",
    primary_skill: require_option(options, "primary_skill"),
    fallback_skill: options["fallback_skill"].to_s,
    skill_status: options["skill_status"] || "completed",
    artifact_name: require_option(options, "artifact_name"),
    artifact_content_file: options["artifact_content_file"],
    artifact_content: options["artifact_content"],
    artifact_status: options["artifact_status"] || "draft",
    gate_status: options["gate_status"] || "conditional_pass",
    gate_result: options["gate_result"].to_s,
    review_roles: options["review_roles"].to_s,
    source_ref: options["source_ref"].to_s
  )
when "export-obsidian"
  runtime.export_obsidian(
    project_id: require_option(options, "project_id"),
    output_dir: require_option(options, "output_dir")
  )
else
  warn "Usage: ruby runtime/pco_runtime.rb <command> [--db PATH] [--workspace PATH] ..."
  warn "Commands: init-project, save-artifact, write-decision, write-review-item, write-agent-memory, build-context-packet, record-invocation, write-raw-review-record, route-intent, record-review-decision, record-turn, export-obsidian"
  exit 1
end
