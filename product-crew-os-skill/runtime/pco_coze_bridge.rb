#!/usr/bin/env ruby

require "json"
require "open3"
require "rbconfig"
require "securerandom"
require "webrick"
require_relative "source_extractor"

# HTTP adapter for a Coze Workflow. It deliberately delegates all persistent
# work to pco_runtime.rb so Coze cannot bypass route traces, packets, ledgers,
# or stage-gate evidence by writing a polished answer directly in a prompt.
class CozeRuntimeBridge
  JSON_HEADERS = { "Content-Type" => "application/json; charset=utf-8" }.freeze
  TRUE_VALUES = %w[1 true yes required].freeze

  def initialize(bind:, port:, workspace:, db:, export_root:)
    @bind = bind
    @port = port
    @workspace = File.expand_path(workspace)
    @db = File.expand_path(db)
    @export_root = File.expand_path(export_root)
    @runtime_path = File.expand_path("pco_runtime.rb", __dir__)
    @token = ENV.fetch("PCO_RUNTIME_TOKEN", "").to_s
    @allow_unauthenticated = TRUE_VALUES.include?(ENV.fetch("PCO_RUNTIME_ALLOW_UNAUTHENTICATED", "").downcase)
    raise "Set PCO_RUNTIME_TOKEN before starting the bridge, or explicitly set PCO_RUNTIME_ALLOW_UNAUTHENTICATED=1 for local-only development." if @token.empty? && !@allow_unauthenticated
  end

  def start
    server = WEBrick::HTTPServer.new(
      BindAddress: @bind,
      Port: @port,
      AccessLog: [],
      Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
    )
    trap("INT") { server.shutdown }
    trap("TERM") { server.shutdown }
    server.mount_proc("/") { |request, response| dispatch(request, response) }
    warn "Product Crew OS Coze bridge listening on http://#{@bind}:#{@port}"
    server.start
  end

  private

  def dispatch(request, response)
    return json(response, 404, error: "not_found") unless known_path?(request.path)
    return json(response, 401, error: "unauthorized") unless authorized?(request)

    case [request.request_method, request.path]
    when ["GET", "/health"]
      json(response, 200, health_payload)
    when ["POST", "/v1/handshake"]
      json(response, 200, handshake_payload)
    when ["POST", "/v1/projects"]
      json(response, 201, runtime("init-project", body(request), %w[project_id name description owner]))
    when ["POST", "/v1/routes"]
      json(response, 200, runtime("route-intent", body(request), %w[project_id user_input]))
    when ["POST", "/v1/skills/execute"]
      json(response, 200, execute_skill(body(request)))
    when ["POST", "/v1/skills/host-callback"]
      json(response, 201, runtime("record-host-skill-execution", body(request), %w[project_id stage_id skill_id runtime_model_id host_run_id raw_output observed_actions_json source_ref]))
    when ["POST", "/v1/rag/ingest"]
      json(response, 201, rag_ingest(body(request)))
    when ["POST", "/v1/rag/retrieve"]
      json(response, 200, runtime("rag-retrieve", body(request), %w[query namespace top_k allowed_scopes consent_ref]))
    when ["POST", "/v1/rag/evidence"]
      json(response, 201, runtime("attach-rag-evidence", body(request), %w[project_id stage_run_id artifact_id source_refs usage]))
    when ["POST", "/v1/turns"]
      json(response, 201, record_turn(body(request)))
    when ["POST", "/v1/reviews/prepare"]
      json(response, 201, runtime("prepare-external-review", body(request), %w[project_id stage_id artifact_id required_roles review_question review_scope evidence_boundary token_budget]))
    when ["POST", "/v1/reviews/callback"]
      json(response, 201, record_real_review_callback(body(request)))
    when ["POST", "/v1/review-items"]
      json(response, 201, runtime("write-review-item", body(request), %w[project_id comment session_id role_key reviewer_name artifact_id stage_id artifact_ref conclusion priority evidence_level user_decision recommendation status source_ref]))
    when ["POST", "/v1/review-decisions"]
      json(response, 201, runtime("record-review-decision", body(request), %w[project_id session_id action item_ids user_confirmed notes]))
    when ["POST", "/v1/gates/finalize"]
      json(response, 200, runtime("finalize-stage-gate", body(request), %w[project_id stage_id artifact_id stage_run_id review_session_id requested_gate_status gate_result user_confirmed decision_note]))
    when ["POST", "/v1/exports/obsidian"]
      json(response, 201, export_obsidian(body(request)))
    else
      json(response, 405, error: "method_not_allowed")
    end
  rescue JSON::ParserError
    json(response, 400, error: "invalid_json")
  rescue RuntimeError => error
    json(response, 422, error: "runtime_rejected", message: error.message)
  rescue StandardError => error
    warn "bridge error: #{error.class}: #{error.message}"
    json(response, 500, error: "bridge_error", message: "Runtime bridge failed. Check the server log for the request id.", request_id: SecureRandom.hex(8))
  end

  def known_path?(path)
    %w[
      /health
      /v1/handshake
      /v1/projects
      /v1/routes
      /v1/skills/execute
      /v1/skills/host-callback
      /v1/rag/ingest
      /v1/rag/retrieve
      /v1/rag/evidence
      /v1/turns
      /v1/reviews/prepare
      /v1/reviews/callback
      /v1/review-items
      /v1/review-decisions
      /v1/gates/finalize
      /v1/exports/obsidian
    ].include?(path)
  end

  def authorized?(request)
    return true if @allow_unauthenticated

    supplied = request["Authorization"].to_s.sub(/\ABearer\s+/i, "")
    secure_equal?(supplied, @token)
  end

  def secure_equal?(left, right)
    return false if left.bytesize != right.bytesize

    left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
  end

  def body(request)
    payload = request.body.to_s.strip
    payload.empty? ? {} : JSON.parse(payload)
  end

  def json(response, status, payload)
    JSON_HEADERS.each { |key, value| response[key] = value }
    response.status = status
    response.body = JSON.generate(payload)
  end

  def runtime(command, payload, allowed_keys)
    payload = stringify_keys(payload)
    project_id = payload["project_id"]
    validate_project_id!(project_id) if project_id
    args = [RbConfig.ruby, @runtime_path, command, "--workspace", @workspace, "--db", @db]
    allowed_keys.each do |key|
      next unless payload.key?(key)
      next if payload[key].nil?

      args << "--#{key.tr('_', '-')}"
      args << option_value(payload[key])
    end
    stdout, stderr, status = Open3.capture3(*args)
    raise "#{command} failed: #{stderr.strip.empty? ? stdout.strip : stderr.strip}" unless status.success?

    JSON.parse(stdout)
  rescue JSON::ParserError
    raise "#{command} returned invalid JSON"
  end

  def record_turn(payload)
    payload = stringify_keys(payload)
    raise "route_decision_id is required; call /v1/routes before /v1/turns" if payload["route_decision_id"].to_s.strip.empty?
    skill_execution = payload.delete("skill_execution")
    if skill_execution
      raise "skill_execution must be an object" unless skill_execution.is_a?(Hash)

      payload["skill_contract_json"] = JSON.generate(skill_execution)
    end
    # Reviewer selection belongs to the immutable route decision. Coze may add
    # evidence, but it may not omit required/triggered roles or choose none.
    payload.delete("review_roles")
    payload["review_mode"] = "standard_sop"
    runtime(
      "record-turn",
      payload,
      %w[project_id stage_id macro_stage sop_id user_input route_confidence route_decision_id primary_skill fallback_skill skill_status skill_contract_json skill_execution_id artifact_name artifact_content artifact_status gate_status gate_result review_roles source_ref review_mode review_question review_scope evidence_boundary]
    )
  end

  def execute_skill(payload)
    payload = stringify_keys(payload)
    skill_id = payload["skill_id"].to_s
    raise "missing skill_id" if skill_id.empty?
    input = payload.fetch("input", {})
    raise "skill input must be an object" unless input.is_a?(Hash)

    runtime(
      "execute-skill",
      { "skill_id" => skill_id, "input_json" => JSON.generate(input) },
      %w[skill_id input_json]
    )
  end

  def rag_ingest(payload)
    payload = stringify_keys(payload)
    metadata = payload.delete("metadata") || {}
    payload["metadata_json"] = JSON.generate(metadata)
    runtime(
      "rag-ingest",
      payload,
      %w[namespace scope source_ref title content source_type extraction_method consent_ref public_package_allowed metadata_json]
    )
  end

  def record_real_review_callback(payload)
    payload = stringify_keys(payload)
    required = %w[project_id session_id role_key stage_id artifact_id context_packet_id runtime_agent_id raw_review conclusion]
    missing = required.select { |key| payload[key].to_s.strip.empty? }
    raise "missing callback fields: #{missing.join(', ')}" unless missing.empty?

    invocation = runtime(
      "record-invocation",
      payload.merge(
        "real" => true,
        "required_for_gate" => true,
        "trigger_reason" => payload["trigger_reason"].to_s.empty? ? "coze_workflow_sub_bot_callback" : payload["trigger_reason"],
        "invocation_status" => payload["invocation_status"].to_s.empty? ? "completed" : payload["invocation_status"],
        "result" => payload["result"].to_s.empty? ? payload["conclusion"] : payload["result"]
      ),
      %w[project_id role_key role_title display_name session_id stage_id artifact_id trigger_reason runtime_agent_id runtime_nickname context_packet_id real invocation_status timeout_seconds required_for_gate result]
    )
    raw_record = runtime(
      "write-raw-review-record",
      payload.merge("invocation_id" => invocation.fetch("invocation_id")),
      %w[project_id session_id role_key artifact_id context_packet_id invocation_id conclusion raw_review]
    )
    review_items = Array(payload["review_items"])
    item_results = review_items.map do |item|
      item_payload = stringify_keys(item).merge(
        "project_id" => payload["project_id"],
        "session_id" => payload["session_id"],
        "role_key" => payload["role_key"],
        "artifact_id" => payload["artifact_id"],
        "stage_id" => payload["stage_id"],
        "conclusion" => item.fetch("conclusion", payload["conclusion"]),
        "source_ref" => item.fetch("source_ref", "coze-invocation:#{invocation.fetch("invocation_id")}")
      )
      runtime(
        "write-review-item",
        item_payload,
        %w[project_id comment session_id role_key reviewer_name artifact_id stage_id artifact_ref conclusion priority evidence_level user_decision recommendation status source_ref]
      )
    end
    {
      real_invocation_performed: true,
      invocation: invocation,
      raw_review_record: raw_record,
      review_items: item_results
    }
  end

  def export_obsidian(payload)
    payload = stringify_keys(payload)
    validate_project_id!(payload.fetch("project_id"))
    runtime(
      "export-obsidian",
      payload.merge("output_dir" => @export_root),
      %w[project_id output_dir]
    )
  end

  def health_payload
    {
      status: "ok",
      service: "product-crew-os-coze-bridge",
      runtime_path: @runtime_path,
      workspace: @workspace,
      authentication_required: !@allow_unauthenticated
    }
  end

  def handshake_payload
    standard_embedding_configured = TRUE_VALUES.include?(ENV.fetch("PCO_STAGE_ROUTER_EMBEDDING", "").downcase)
    delegate_configured = ENV.fetch("PCO_COZE_SUBAGENT_DELEGATE", "").to_s == "workflow_callback"
    vector_stats = persistent_vector_stats
    ocr_capability = ProductCrewOS::SourceExtractor.new.capability
    capabilities = {
      route_trace_writer: { configured: true, evidence: "runtime route-intent writes routing/stage-route-decision.jsonl" },
      sop_router: { configured: true, evidence: "runtime stage router" },
      skill_router: { configured: true, evidence: "Coze must pass selected_skill into record-turn" },
      project_database: { configured: true, evidence: "SQLite Runtime database" },
      artifact_writer: { configured: true, evidence: "runtime save-artifact" },
      real_embedding_provider: { configured: standard_embedding_configured, observed_per_turn: true, evidence: "route trace real_embedding_performed" },
      vector_index: { configured: standard_embedding_configured, observed_per_turn: true, chunks: vector_stats[:chunks], engine: vector_stats[:engine], evidence: "persistent pco_rules vectors and embedding_retrieval_events" },
      local_ocr: { configured: ocr_capability["paddleocr"] || ocr_capability["tesseract"], required_for_standard_sop: false, engines: ocr_capability, evidence: "Runtime SourceExtractor capability probe; required only for image/PDF OCR ingestion" },
      subagent_delegate: { configured: delegate_configured, observed_per_turn: true, evidence: "Coze Bot callback with runtime_agent_id" },
      invocation_ledger: { configured: true, evidence: "agent_invocations" },
      raw_review_writer: { configured: true, evidence: "raw_review_records" }
    }
    missing = capabilities.select { |_key, value| !value[:configured] && value.fetch(:required_for_standard_sop, true) }.keys
    {
      runtime_status: missing.empty? ? "ready_for_standard_sop" : "runtime_degraded",
      configured_capabilities: capabilities,
      missing_capabilities: missing,
      per_turn_proof_required: %w[real_embedding_performed runtime_agent_id context_packet_quality raw_review_record],
      gate_when_missing: "blocked_runtime_preflight"
    }
  end

  def stringify_keys(value)
    return value.map { |item| stringify_keys(item) } if value.is_a?(Array)
    return value unless value.is_a?(Hash)

    value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
  end

  def persistent_vector_stats
    return { chunks: 0, engine: "not_initialized" } unless File.exist?(@db)

    stdout, _stderr, status = Open3.capture3("sqlite3", "-json", @db, "SELECT COUNT(*) AS chunks FROM embedding_chunks WHERE deleted_at = '' AND stale = 0;")
    chunks = status.success? ? JSON.parse(stdout).first.fetch("chunks").to_i : 0
    engine = "not_initialized"
    index_stdout, _index_stderr, index_status = Open3.capture3("sqlite3", "-json", @db, "SELECT engine FROM embedding_vector_indexes ORDER BY updated_at DESC LIMIT 1;")
    engine = JSON.parse(index_stdout).first.fetch("engine") if index_status.success? && !index_stdout.strip.empty?
    { chunks: chunks, engine: engine }
  rescue JSON::ParserError
    { chunks: 0, engine: "not_initialized" }
  end

  def option_value(value)
    case value
    when Array
      value.join(",")
    when TrueClass, FalseClass
      value ? "true" : "false"
    else
      value.to_s
    end
  end

  def validate_project_id!(project_id)
    raise "invalid project_id" unless project_id.to_s.match?(/\A[0-9A-Za-z_\-]{1,80}\z/)
  end
end

options = {
  bind: ENV.fetch("PCO_RUNTIME_BIND", "127.0.0.1"),
  port: ENV.fetch("PCO_RUNTIME_PORT", "8787").to_i,
  workspace: ENV.fetch("PCO_RUNTIME_WORKSPACE", File.expand_path("runtime-workspace", Dir.pwd)),
  db: ENV.fetch("PCO_RUNTIME_DB", ""),
  export_root: ENV.fetch("PCO_RUNTIME_EXPORT_ROOT", File.expand_path("runtime-exports", Dir.pwd))
}
options[:db] = File.join(options[:workspace], "product-crew-os.sqlite3") if options[:db].empty?

CozeRuntimeBridge.new(**options).start
