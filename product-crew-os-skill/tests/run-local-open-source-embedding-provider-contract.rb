#!/usr/bin/env ruby

require "fileutils"
require "json"
require "time"
require_relative "../runtime/embedding_provider"
require_relative "../runtime/sop_embedding_index"
require_relative "../runtime/stage_router"

skill_root = File.expand_path("..", __dir__)
results_dir = File.join(skill_root, "tests", "results")
latest_report = File.join(results_dir, "local-open-source-embedding-provider-contract-latest.md")
latest_json = File.join(results_dir, "local-open-source-embedding-provider-contract-latest.json")

errors = []
status = "runtime_blocked_missing_local_model"
result = nil

provider = ProductCrewOS::EmbeddingProviders.build(provider: "local_open_source_bge_small_zh")

if provider.available?
  begin
    result = provider.embed("Product Crew OS 语义阶段路由")
    batch = provider.embed_batch(["MVP 范围", "核心流程图"])
    index = ProductCrewOS::SopEmbeddingIndex.new(prompt_eval_path: File.join(skill_root, "tests", "prompt-eval-cases.yaml"), provider: provider)
    index_result = index.retrieve("我来定：第一阶段就做审核工作台 AI 辅助判定 + 知识库 RAG 联动。", top_k: 3)
    router = SemanticStageRouter.new(prompt_eval_path: File.join(skill_root, "tests", "prompt-eval-cases.yaml"), embedding_mode: "real")
    route = router.route("我来定：第一阶段就做审核工作台 AI 辅助判定 + 知识库 RAG 联动。")
    errors << "provider id mismatch" unless result["provider"] == "local_open_source_bge_small_zh"
    errors << "model mismatch" unless result["model"].to_s.include?("bge-small-zh")
    errors << "embedding dim must be positive" unless result["embedding_dim"].to_i.positive?
    errors << "real_embedding_performed must be true" unless result["real_embedding_performed"] == true
    errors << "embed_batch must return two embeddings" unless batch.length == 2 && batch.all? { |item| item["real_embedding_performed"] == true }
    errors << "SOP embedding index must use real embedding" unless index_result["real_embedding_performed"] == true
    errors << "SOP embedding index must return top-k candidates" unless index_result["candidates"].is_a?(Array) && !index_result["candidates"].empty?
    errors << "StageRouter must expose real embedding evidence" unless route["real_embedding_performed"] == true && route["retrieval_mode"] == "real_embedding_sop_rag"
    status = errors.empty? ? "real_local_call_passed" : "real_local_call_failed"
  rescue ProductCrewOS::EmbeddingProviders::ProviderError => e
    errors << e.message
    status = e.message.include?("runtime_blocked_timeout") ? "runtime_blocked_timeout" : "runtime_blocked_missing_local_model"
  end
else
  errors << "runtime_blocked_missing_local_model: install sentence-transformers or FlagEmbedding, then ensure BAAI/bge-small-zh-v1.5 is available locally"
end

payload = {
  "status" => status,
  "generated_at" => Time.now.utc.iso8601,
  "provider" => "local_open_source_bge_small_zh",
  "model" => provider.model,
  "python_bin" => provider.python_bin,
  "real_embedding_performed" => result ? result["real_embedding_performed"] : false,
  "result" => result&.reject { |key, _| key == "vector" },
  "sop_embedding_index" => defined?(index_result) && index_result ? index_result.reject { |key, _| key == "vector" } : {},
  "stage_router" => defined?(route) && route ? route.select { |key, _| %w[stage_id retrieval_mode real_embedding_performed embedding_provider embedding_model].include?(key) } : {},
  "errors" => errors
}

FileUtils.mkdir_p(results_dir)
File.write(latest_json, JSON.pretty_generate(payload))

lines = [
  "# Local Open-Source Embedding Provider Contract",
  "",
  "- Status: `#{status}`",
  "- Provider: `local_open_source_bge_small_zh`",
  "- Model: `#{provider.model}`",
  "- Python: `#{provider.python_bin}`",
  "- Real embedding performed: `#{payload["real_embedding_performed"]}`",
  ""
]

if errors.empty?
  lines << "## Errors"
  lines << ""
  lines << "- None"
else
  lines << "## Errors"
  lines << ""
  errors.each { |error| lines << "- #{error}" }
end

File.write(latest_report, lines.join("\n"))

puts "run-local-open-source-embedding-provider-contract: #{status == "real_local_call_passed" ? "PASS" : "RUNTIME_BLOCKED"}"
puts "provider_status: #{status}"
puts "real_embedding_performed: #{payload["real_embedding_performed"]}"
puts "report: #{latest_report}"
exit(status == "real_local_call_passed" ? 0 : 3)
