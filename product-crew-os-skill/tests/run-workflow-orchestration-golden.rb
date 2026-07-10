#!/usr/bin/env ruby

require "fileutils"
require "time"
require "yaml"

skill_root = File.expand_path("..", __dir__)
map_path = File.join(skill_root, "references", "workflow-orchestration-map-v0.yaml")
result_dir = File.join(skill_root, "tests", "results")
result_path = File.join(result_dir, "latest-workflow-orchestration.md")

errors = []
warnings = []
check_only = ARGV.include?("--check-only")

def assert(errors, condition, message)
  errors << message unless condition
end

unless File.exist?(map_path)
  warn "run-workflow-orchestration-golden: FAIL"
  warn "- missing workflow orchestration map: #{map_path}"
  exit 1
end

map = YAML.load_file(map_path)
flows = map["macro_flows"] || []
claim_boundary = map["claim_boundary"] || {}
completion_definition = map["completion_definition"] || {}
skill_status_values = map["skill_status_values"] || []

assert(errors, map["schema_version"].to_s != "", "workflow orchestration map missing schema_version")
assert(errors, map["map_kind"] == "workflow_orchestration_map", "workflow orchestration map kind mismatch")
assert(errors, claim_boundary["macro_flows_total"].to_i == 10, "claim boundary must declare 10 macro flows")
assert(errors, flows.length == 10, "workflow orchestration map should list 10 macro flows, found #{flows.length}")

required_skill_statuses = %w[primary_hit fallback_hit template_degraded missing runtime_blocked]
required_skill_statuses.each do |status|
  assert(errors, skill_status_values.include?(status), "skill_status_values missing #{status}")
end

required_completion_checks = %w[
  flow_map_defined
  state_machine_path_defined
  artifact_chain_defined
  primary_skill_assertions_defined
  required_and_triggered_roles_defined
  invocation_ledger_assertions_defined
  gate_evidence_defined
  golden_case_replayable
]
actual_completion_checks = completion_definition["required_for_full_macro_flow"] || []
required_completion_checks.each do |check|
  assert(errors, actual_completion_checks.include?(check), "completion definition missing #{check}")
end

expected_flow_ids = %w[
  flow_01_opportunity_discovery
  flow_02_user_research
  flow_03_problem_framing
  flow_04_requirement_analysis
  flow_05_solution_design
  flow_06_prd_drafting
  flow_07_cross_functional_review
  flow_08_delivery_planning
  flow_09_launch_readiness
  flow_10_post_launch_review
]

flow_ids = flows.map { |flow| flow["flow_id"] }
assert(errors, flow_ids.uniq.length == flow_ids.length, "workflow orchestration map has duplicate flow_id")
expected_flow_ids.each do |flow_id|
  assert(errors, flow_ids.include?(flow_id), "workflow orchestration map missing #{flow_id}")
end

complete_flows = []
partial_flows = []
not_started_flows = []

flows.each do |flow|
  flow_id = flow["flow_id"] || "unknown"
  implementation_status = flow["implementation_status"]
  current_evidence = flow["current_evidence"] || {}
  golden_case = flow["golden_case"] || {}
  stages = flow["stages"] || []
  artifacts = flow["artifacts"] || []
  gate = flow["gate"] || {}

  %w[flow_id title user_visible_goal implementation_status current_evidence stages artifacts required_roles triggered_roles gate golden_case missing_assertions].each do |field|
    assert(errors, flow.key?(field), "#{flow_id} missing #{field}")
  end

  assert(errors, %w[not_started partial complete runtime_blocked].include?(implementation_status), "#{flow_id} invalid implementation_status #{implementation_status.inspect}")
  assert(errors, [true, false].include?(flow["completion_qualifies_as_full_macro_flow"]), "#{flow_id} missing boolean completion_qualifies_as_full_macro_flow")
  assert(errors, stages.any?, "#{flow_id} must define at least one stage")
  assert(errors, artifacts.any?, "#{flow_id} must define artifacts")
  assert(errors, Array(flow["required_roles"]).include?("Coach"), "#{flow_id} required_roles must include Coach")
  assert(errors, (gate["status_values"] || []).sort == %w[block conditional_pass pass rollback].sort, "#{flow_id} gate status values must include pass/conditional_pass/block/rollback")

  stages.each do |stage|
    assert(errors, stage["stage_id"].to_s != "", "#{flow_id} stage missing stage_id")
    assert(errors, Array(stage["sop_ids"]).any?, "#{flow_id} stage #{stage["stage_id"]} missing sop_ids")
    assert(errors, Array(stage["required_artifacts"]).any?, "#{flow_id} stage #{stage["stage_id"]} missing required_artifacts")
  end

  %w[sop_router_status runtime_smoke_status full_state_machine_status golden_case_status].each do |field|
    assert(errors, current_evidence[field].to_s != "", "#{flow_id} current_evidence missing #{field}")
  end

  assert(errors, %w[missing partial complete].include?(golden_case["status"]), "#{flow_id} golden_case.status must be missing/partial/complete")

  if golden_case["status"] == "complete" || implementation_status == "complete" || flow["completion_qualifies_as_full_macro_flow"] == true
    complete_candidate = implementation_status == "complete" &&
      flow["completion_qualifies_as_full_macro_flow"] == true &&
      golden_case["status"] == "complete"
    if complete_candidate
      complete_flows << flow_id
    else
      errors << "#{flow_id} has inconsistent completion flags"
    end
  elsif implementation_status == "partial" || golden_case["status"] == "partial"
    partial_flows << flow_id
  else
    not_started_flows << flow_id
  end

  Array(golden_case["existing_files"]).each do |relative_path|
    path = File.join(skill_root, relative_path)
    assert(errors, File.exist?(path), "#{flow_id} points to missing golden case file #{relative_path}")
  end
end

claimed_complete = claim_boundary["full_macro_flows_complete"].to_i
assert(errors, complete_flows.length == claimed_complete, "claim boundary full_macro_flows_complete #{claimed_complete} does not match complete flows #{complete_flows.length}")
assert(errors, complete_flows == ["flow_01_opportunity_discovery"], "only flow_01 should be complete in this release slice, found #{complete_flows.join(", ")}")
assert(errors, complete_flows.length + partial_flows.length + not_started_flows.length == flows.length, "complete/partial/not_started flow counts should cover all macro flows")
assert(errors, partial_flows.length + not_started_flows.length == 9, "only one flow should be complete in this release slice")

flow_01_full_path = File.join(skill_root, "tests", "golden-cases", "flow-01-opportunity-discovery-full.yaml")
if File.exist?(flow_01_full_path)
  flow_01_full = YAML.load_file(flow_01_full_path)
  assert(errors, flow_01_full["case_id"] == "flow_01_opportunity_discovery_full", "flow_01 full golden case id mismatch")
  assert(errors, flow_01_full["main_flow_id"] == "flow_01_opportunity_discovery", "flow_01 full golden case main_flow_id mismatch")
  assert(errors, flow_01_full["fixture_type"] == "synthetic_case", "flow_01 full golden case must be synthetic")
  assert(errors, flow_01_full["real_runtime_claim"] == false, "flow_01 full golden case must not claim real runtime")

  expected_sops = %w[00 01 02 03 04 05]
  selected_sops = (flow_01_full.dig("sop_composition", "selected_sops") || []).map { |sop| sop["sop_id"] }
  expected_sops.each do |sop_id|
    assert(errors, selected_sops.include?(sop_id), "flow_01 full golden case missing SOP #{sop_id}")
  end

  skill_router_log = flow_01_full["skill_router_log"] || []
  assert(errors, skill_router_log.length >= 6, "flow_01 full golden case should include at least 6 skill calls")
  skill_router_log.each do |skill_call|
    %w[expected_primary_skill selected_skill skill_status fallback_used].each do |field|
      assert(errors, skill_call.key?(field), "flow_01 full skill call missing #{field}")
    end
    assert(errors, skill_call["skill_status"] != "template_degraded", "flow_01 full must not count template_degraded as complete")
    assert(errors, %w[primary_hit fallback_hit].include?(skill_call["skill_status"]), "flow_01 full invalid complete skill_status #{skill_call["skill_status"].inspect}")
  end

  required_packet_fields = %w[
    role_key title display_name role personality speaking_style must_do must_not_do
    memory_focus persona_source_ref stage_id review_scope evidence_boundary
    context_packet_quality persona_injection_status
  ]
  context_packets = flow_01_full["context_packets"] || []
  %w[Biz Research Data CS Customer].each do |role_key|
    packet = context_packets.find { |item| item["role_key"] == role_key }
    assert(errors, !packet.nil?, "flow_01 full missing context packet for #{role_key}")
    next unless packet

    required_packet_fields.each do |field|
      assert(errors, packet[field].to_s != "", "flow_01 full context packet #{role_key} missing #{field}")
    end
    %w[personality speaking_style must_do must_not_do memory_focus].each do |field|
      assert(errors, Array(packet[field]).any?, "flow_01 full context packet #{role_key} #{field} must be non-empty array")
    end
    assert(errors, packet["context_packet_quality"] == "complete", "flow_01 full context packet #{role_key} should be complete")
    assert(errors, packet["persona_injection_status"] == "complete", "flow_01 full context packet #{role_key} persona injection should be complete")
  end

  invocation_ledger = flow_01_full["invocation_ledger"] || []
  assert(errors, invocation_ledger.length >= 5, "flow_01 full should include all triggered review ledger entries")
  invocation_ledger.each do |entry|
    assert(errors, entry["context_packet_quality"] == "complete", "flow_01 full ledger #{entry["invocation_id"]} missing complete context quality")
    assert(errors, entry["persona_injection_status"] == "complete", "flow_01 full ledger #{entry["invocation_id"]} missing complete persona injection")
    assert(errors, entry["real_invocation_performed"] == false, "flow_01 full synthetic fixture must not mark real invocation")
    assert(errors, entry["simulation_label"] == "synthetic_fixture", "flow_01 full synthetic fixture missing simulation label")
  end

  negative_paths = flow_01_full["negative_paths"] || []
  required_negative_paths = {
    "F01-NON-PRODUCT-EXIT" => {
      "expected_result" => "exit_product_crew_os",
      "must_not_call_skills" => true,
      "must_not_call_agents" => true
    },
    "F01-EVIDENCE-GAP-BLOCK" => {
      "expected_result" => "block",
      "required_artifact_update" => "open-questions.md"
    },
    "F01-USER-STAGE-CORRECTION" => {
      "expected_result" => "rollback_to_corrected_stage",
      "required_artifact_update" => "decision-log.md"
    }
  }
  required_negative_paths.each do |path_id, expectations|
    path = negative_paths.find { |item| item["path_id"] == path_id }
    assert(errors, !path.nil?, "flow_01 full missing negative path #{path_id}")
    next unless path

    assert(errors, Array(path["expected_state_path"]).any?, "flow_01 full negative path #{path_id} missing expected_state_path")
    expectations.each do |field, expected_value|
      assert(errors, path[field] == expected_value, "flow_01 full negative path #{path_id} expected #{field}=#{expected_value.inspect}")
    end
  end

  coverage_delta = flow_01_full["coverage_delta"] || {}
  assert(errors, coverage_delta["before"] == "0/10", "flow_01 full coverage delta missing before=0/10")
  assert(errors, coverage_delta["delta"] == "+1", "flow_01 full coverage delta missing delta=+1")
  assert(errors, coverage_delta["after"] == "1/10", "flow_01 full coverage delta missing after=1/10")
  assert(errors, coverage_delta["remaining_macro_flows"].to_i == 9, "flow_01 full coverage delta should leave 9 remaining macro flows")
  assert(errors, coverage_delta["full_macro_flows_complete_after_case"].to_i == 1, "flow_01 full coverage delta should move macro flow counter to 1")

  measurement_plan = flow_01_full["measurement_plan"] || {}
  assert(errors, measurement_plan["metric_contract_status"] == "candidate_validation_metrics_not_data_contract", "flow_01 full measurement plan must not claim full data contract")
  (measurement_plan["metrics"] || []).each do |metric|
    %w[field_availability update_frequency freshness_requirement attribution_window instrumentation_requirements].each do |field|
      assert(errors, metric[field].to_s != "", "flow_01 full metric #{metric["metric_id"]} missing #{field}")
    end
    assert(errors, Array(metric["instrumentation_requirements"]).any?, "flow_01 full metric #{metric["metric_id"]} missing instrumentation requirements")
  end
else
  errors << "missing flow_01 full golden case file"
end

coverage_path = File.join(skill_root, "references", "workflow-implementation-coverage-v0.yaml")
if File.exist?(coverage_path)
  coverage = YAML.load_file(coverage_path)
  summary = coverage["coverage_summary"] || {}
  assert(errors, summary["full_macro_flows_complete"].to_i == complete_flows.length, "coverage summary full_macro_flows_complete should match orchestration map")
  assert(errors, summary["macro_flows_total"].to_i == 10, "coverage summary should still declare 10 macro flows")
else
  warnings << "workflow implementation coverage yaml not found; skipped cross-check"
end

generated_at = Time.now.utc.iso8601
FileUtils.mkdir_p(result_dir)

if errors.empty?
  unless check_only
    File.write(result_path, <<~MARKDOWN)
    # Workflow Orchestration Golden Result

    status: PASS
    generated_at: #{generated_at}
    map: references/workflow-orchestration-map-v0.yaml

    summary:
    - macro_flows_total: #{flows.length}
    - complete_macro_flows: #{complete_flows.length}
    - partial_macro_flows: #{partial_flows.length}
    - not_started_macro_flows: #{not_started_flows.length}

    complete_flows:
    #{complete_flows.map { |flow_id| "- #{flow_id}" }.join("\n")}

    partial_flows:
    #{partial_flows.map { |flow_id| "- #{flow_id}" }.join("\n")}

    not_started_flows:
    #{not_started_flows.map { |flow_id| "- #{flow_id}" }.join("\n")}

    warnings:
    #{warnings.empty? ? "- none" : warnings.map { |warning| "- #{warning}" }.join("\n")}
  MARKDOWN
  end

  puts "run-workflow-orchestration-golden: PASS"
  puts "complete_macro_flows: #{complete_flows.length}/10"
  puts "partial_macro_flows: #{partial_flows.length}/10"
  puts "not_started_macro_flows: #{not_started_flows.length}/10"
  puts "result: #{check_only ? "not written (--check-only)" : result_path}"
else
  unless check_only
    File.write(result_path, <<~MARKDOWN)
    # Workflow Orchestration Golden Result

    status: FAIL
    generated_at: #{generated_at}
    map: references/workflow-orchestration-map-v0.yaml

    errors:
    #{errors.map { |error| "- #{error}" }.join("\n")}
  MARKDOWN
  end

  warn "run-workflow-orchestration-golden: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
