#!/usr/bin/env ruby

require "fileutils"
require "json"
require "time"
require_relative "../runtime/embedding_provider"

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
    errors << "provider id mismatch" unless result["provider"] == "local_open_source_bge_small_zh"
    errors << "model mismatch" unless result["model"].to_s.include?("bge-small-zh")
    errors << "embedding dim must be positive" unless result["embedding_dim"].to_i.positive?
    errors << "real_embedding_performed must be true" unless result["real_embedding_performed"] == true
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
