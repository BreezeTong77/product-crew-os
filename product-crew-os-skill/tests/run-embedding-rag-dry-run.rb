#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "set"
require "time"
require "yaml"
require_relative "../runtime/stage_router"

skill_root = File.expand_path("..", __dir__)
prompt_eval_path = File.join(skill_root, "tests", "prompt-eval-cases.yaml")
external_cases_path = File.join(skill_root, "tests", "external-benchmark-cases.yaml")
policy_path = File.join(skill_root, "config", "embedding-rag-policy.yaml")
results_dir = File.join(skill_root, "tests", "results")
output_dir = ARGV[0] || File.join(results_dir, "embedding-rag-dry-run-#{Time.now.strftime("%Y%m%d-%H%M%S")}")
latest_report = File.join(results_dir, "embedding-rag-dry-run-latest.md")
latest_json = File.join(results_dir, "embedding-rag-dry-run-latest.json")

RETRIEVAL_STOP_TERMS = %w[
  帮我 我想 我有 我要 我们 一下 一个 一版 这个 那个 做个 做一 我做 帮我做
  整理 我整 我整理 帮我整 看下 我看 帮我看 怎么 如何 一下子 help please one
].freeze

def tokenize(text)
  raw = text.to_s.downcase
  latin_tokens = raw.scan(/[a-z0-9_]{2,}/)
  han_text = raw.scan(/\p{Han}+/).join
  han_chars = han_text.chars
  han_bigrams = han_chars.each_cons(2).map(&:join)
  han_trigrams = han_chars.each_cons(3).map(&:join)
  (latin_tokens + han_bigrams + han_trigrams).reject(&:empty?).reject { |token| RETRIEVAL_STOP_TERMS.include?(token) }
end

def normalized_vector(text)
  counts = Hash.new(0.0)
  tokenize(text).each { |token| counts[token] += 1.0 }
  norm = Math.sqrt(counts.values.sum { |value| value * value })
  return {} if norm.zero?

  counts.transform_values { |value| value / norm }
end

STAGE_ALIAS_TEXT = {
  "request_triage" => "Product Crew OS SOP skill Stage Agent artifact workflow router 子 Agent 调用逻辑 机制 测试 评估 修改 配置 发布包 不知道先处理哪个 下一步怎么走 判断阶段",
  "formal_requirements_review" => "按标准 SOP 评审 PRD 正式需求评审 评审结论 通过 条件通过 驳回 stakeholder alignment",
  "low_fi_prototype" => "原型图 低保真 wireframe mockup UI 草图 截图 参考图",
  "technical_pre_review" => "研发 技术预评审 系统边界 权限 接口 依赖 工期 风险",
  "metrics_design" => "北极星指标 输入指标 护栏指标 指标树 north star metrics",
  "data_feasibility_precheck" => "数据可行性 推荐逻辑 字段 来源 新鲜度 数据合同 data contract",
  "launch_readiness" => "准备上线 上线检查 发布检查 go no go go/no-go launch readiness 灰度 监控 回滚 客服 运营 就绪",
  "one_page_proposal" => "一页方案 一页纸 one pager one-page exec summary 业务方 过方向 资源申请",
  "prioritization" => "优先级 排序 RICE ICE MoSCoW 哪些先做 哪些先不做 above line below line"
}.freeze

def cosine(left, right)
  return 0.0 if left.empty? || right.empty?

  small, large = left.length < right.length ? [left, right] : [right, left]
  small.sum { |token, value| value * large.fetch(token, 0.0) }
end

def case_text(entry)
  expected = entry.fetch("expected")
  [
    entry.fetch("case_id"),
    entry.fetch("stage_id"),
    entry.fetch("stage_id").tr("_", " "),
    entry.fetch("macro_stage"),
    entry.fetch("user_input"),
    STAGE_ALIAS_TEXT[entry.fetch("stage_id")],
    expected["primary_skill"],
    expected["fallback_skill"],
    Array(expected["required_roles"]).join(" "),
    Array(expected["triggered_roles"]).join(" "),
    Array(expected["required_artifacts"]).join(" "),
    expected["stage_gate"],
    Array(expected["must_not"]).join(" ")
  ].compact.join(" ")
end

class DryRunEmbeddingIndex
  attr_reader :documents

  def initialize(documents)
    @documents = documents.map do |doc|
      doc.merge("vector" => normalized_vector(doc.fetch("text")))
    end
  end

  def query(text, top_k:)
    query_vector = normalized_vector(text)
    @documents.map do |doc|
      doc.merge("score" => cosine(query_vector, doc.fetch("vector")).round(4))
    end.reject { |doc| doc.fetch("score").zero? }
      .sort_by { |doc| [-doc.fetch("score"), doc.fetch("stage_id")] }
      .first(top_k)
  end
end

def ratio(numerator, denominator)
  return 1.0 if denominator.zero?

  numerator.to_f / denominator
end

policy = YAML.load_file(policy_path)
top_k = policy.dig("retrieval_contract", "top_k").to_i
top_k = 5 if top_k <= 0
prompt_eval = YAML.load_file(prompt_eval_path)
external_cases = YAML.load_file(external_cases_path).fetch("cases")
router = SemanticStageRouter.new(prompt_eval_path: prompt_eval_path)

documents = prompt_eval.fetch("cases").map do |entry|
  {
    "doc_id" => "pco_rules:#{entry.fetch("case_id")}",
    "namespace" => "pco_rules",
    "scope" => "product_rule_memory",
    "source_ref" => "tests/prompt-eval-cases.yaml##{entry.fetch("case_id")}",
    "stage_id" => entry.fetch("stage_id"),
    "case_id" => entry.fetch("case_id"),
    "public_package_allowed" => true,
    "consent_required" => false,
    "content_hash" => Digest::SHA256.hexdigest(case_text(entry)),
    "text" => case_text(entry)
  }
end

index = DryRunEmbeddingIndex.new(documents)
evaluated_cases = []
false_positive_domain_entries = 0

external_cases.each do |entry|
  route = router.route(entry.fetch("prompt"))
  expected_domain = entry.fetch("expected_domain_intent")
  if expected_domain == "non_product_task"
    false_positive_domain_entries += 1 if route.fetch("product_crew_os_applies")
    evaluated_cases << {
      "case_id" => entry.fetch("case_id"),
      "expected_domain_intent" => expected_domain,
      "retrieval_skipped" => !route.fetch("product_crew_os_applies"),
      "top_candidates" => []
    }
    next
  end

  candidates = index.query(entry.fetch("prompt"), top_k: top_k)
  candidate_stages = candidates.map { |candidate| candidate.fetch("stage_id") }
  evaluated_cases << {
    "case_id" => entry.fetch("case_id"),
    "expected_domain_intent" => expected_domain,
    "expected_stage_id" => entry.fetch("expected_stage_id"),
    "retrieval_skipped" => false,
    "hit_at_1" => candidate_stages.first == entry.fetch("expected_stage_id"),
    "hit_at_3" => candidate_stages.first(3).include?(entry.fetch("expected_stage_id")),
    "top_candidates" => candidates.map do |candidate|
      {
        "stage_id" => candidate.fetch("stage_id"),
        "score" => candidate.fetch("score"),
        "source_ref" => candidate.fetch("source_ref")
      }
    end
  }
end

product_cases = evaluated_cases.select { |entry| entry.fetch("expected_domain_intent") != "non_product_task" }
non_product_cases = evaluated_cases.select { |entry| entry.fetch("expected_domain_intent") == "non_product_task" }
traceable_docs = documents.count { |doc| doc.fetch("source_ref").to_s != "" && doc.fetch("content_hash").to_s != "" }
namespace_violations = documents.count do |doc|
  doc.fetch("namespace") != "pco_rules" ||
    doc.fetch("scope") != "product_rule_memory" ||
    doc.fetch("public_package_allowed") != true
end

metrics = {
  "provider" => "local_hash_dry_run",
  "real_embedding_performed" => false,
  "documents_indexed" => documents.length,
  "external_cases" => external_cases.length,
  "product_cases" => product_cases.length,
  "non_product_cases" => non_product_cases.length,
  "rag_stage_hit_at_1" => ratio(product_cases.count { |entry| entry["hit_at_1"] }, product_cases.length).round(3),
  "rag_stage_hit_at_3" => ratio(product_cases.count { |entry| entry["hit_at_3"] }, product_cases.length).round(3),
  "false_positive_domain_entry_rate" => ratio(false_positive_domain_entries, non_product_cases.length).round(3),
  "source_trace_rate" => ratio(traceable_docs, documents.length).round(3),
  "namespace_isolation_violations" => namespace_violations
}

minimum_thresholds = {
  "rag_stage_hit_at_1" => policy.dig("metrics", "rag_stage_hit_at_1_min").to_f,
  "rag_stage_hit_at_3" => policy.dig("metrics", "rag_stage_hit_at_3_min").to_f,
  "source_trace_rate" => policy.dig("metrics", "source_trace_rate_min").to_f
}
maximum_thresholds = {
  "false_positive_domain_entry_rate" => policy.dig("metrics", "false_positive_domain_entry_rate_max").to_f,
  "namespace_isolation_violations" => policy.dig("metrics", "namespace_isolation_violation_max").to_i
}
failed_minimums = minimum_thresholds.select { |key, threshold| metrics.fetch(key) < threshold }
failed_maximums = maximum_thresholds.select { |key, threshold| metrics.fetch(key) > threshold }
failed_thresholds = failed_minimums.merge(failed_maximums)
status = failed_thresholds.empty? ? "PASS" : "FAIL"

payload = {
  "status" => status,
  "generated_at" => Time.now.utc.iso8601,
  "metrics" => metrics,
  "minimum_thresholds" => minimum_thresholds,
  "maximum_thresholds" => maximum_thresholds,
  "failed_thresholds" => failed_thresholds,
  "cases" => evaluated_cases
}

FileUtils.mkdir_p(output_dir)
FileUtils.mkdir_p(results_dir)
File.write(File.join(output_dir, "embedding-rag-dry-run-results.json"), JSON.pretty_generate(payload))
File.write(latest_json, JSON.pretty_generate(payload))

lines = [
  "# Embedding RAG Dry Run Report",
  "",
  "- Status: `#{status}`",
  "- Provider: `#{metrics["provider"]}`",
  "- Real embedding performed: `#{metrics["real_embedding_performed"]}`",
  "- Documents indexed: `#{metrics["documents_indexed"]}`",
  "- Product cases: `#{metrics["product_cases"]}`",
  "- Non-product cases: `#{metrics["non_product_cases"]}`",
  "- RAG stage hit@1: `#{metrics["rag_stage_hit_at_1"]}`",
  "- RAG stage hit@3: `#{metrics["rag_stage_hit_at_3"]}`",
  "- False positive domain entry rate: `#{metrics["false_positive_domain_entry_rate"]}`",
  "- Source trace rate: `#{metrics["source_trace_rate"]}`",
  "- Namespace isolation violations: `#{metrics["namespace_isolation_violations"]}`",
  "",
  "## Failed Thresholds",
  ""
]
if failed_thresholds.empty?
  lines << "- None"
else
  failed_thresholds.each do |key, threshold|
    comparator = maximum_thresholds.key?(key) ? "<= #{threshold}" : ">= #{threshold}"
    lines << "- `#{key}` expected #{comparator}, got #{metrics.fetch(key)}"
  end
end

misses = product_cases.reject { |entry| entry["hit_at_3"] }
lines += ["", "## Misses", ""]
if misses.empty?
  lines << "- None"
else
  misses.each do |entry|
    lines << "### #{entry.fetch("case_id")}"
    lines << ""
    lines << "- Expected stage: `#{entry.fetch("expected_stage_id")}`"
    lines << "- Top candidates: #{entry.fetch("top_candidates").map { |candidate| "#{candidate.fetch("stage_id")}:#{candidate.fetch("score")}" }.join(", ")}"
    lines << ""
  end
end

File.write(File.join(output_dir, "embedding-rag-dry-run-report.md"), lines.join("\n"))
File.write(latest_report, lines.join("\n"))

puts "run-embedding-rag-dry-run: #{status}"
metrics.each { |key, value| puts "#{key}: #{value}" }
puts "report: #{latest_report}"
exit(status == "PASS" ? 0 : 2)
