require "digest"
require "json"
require "open3"
require "timeout"

module ProductCrewOS
  module EmbeddingProviders
    class ProviderError < StandardError; end

    class LocalHashDryRun
      DEFAULT_DIM = 256

      attr_reader :model

      def initialize(dim: DEFAULT_DIM)
        @dim = dim
        @model = "local_hash_dry_run"
      end

      def available?
        true
      end

      def embed(text)
        vector = Array.new(@dim, 0.0)
        tokenize(text).each do |token|
          index = Digest::SHA256.hexdigest(token).to_i(16) % @dim
          vector[index] += 1.0
        end
        normalize!(vector)
        {
          "provider" => "local_hash_dry_run",
          "model" => @model,
          "embedding_dim" => vector.length,
          "real_embedding_performed" => false,
          "runtime_status" => "smoke_only_not_user_runtime",
          "vector" => vector
        }
      end

      private

      def tokenize(text)
        raw = text.to_s.downcase
        latin_tokens = raw.scan(/[a-z0-9_]{2,}/)
        han_text = raw.scan(/\p{Han}+/).join
        han_chars = han_text.chars
        han_bigrams = han_chars.each_cons(2).map(&:join)
        han_trigrams = han_chars.each_cons(3).map(&:join)
        (latin_tokens + han_bigrams + han_trigrams).reject(&:empty?)
      end

      def normalize!(vector)
        norm = Math.sqrt(vector.sum { |value| value * value })
        return vector if norm.zero?

        vector.map! { |value| (value / norm).round(8) }
      end
    end

    class LocalOpenSourceBGESmallZH
      DEFAULT_MODEL = "BAAI/bge-small-zh-v1.5"

      attr_reader :model, :python_bin

      def initialize(
        model: ENV["PCO_BGE_MODEL"].to_s.strip.empty? ? DEFAULT_MODEL : ENV["PCO_BGE_MODEL"],
        python_bin: ENV["PCO_EMBEDDING_PYTHON"].to_s.strip.empty? ? "python3" : ENV["PCO_EMBEDDING_PYTHON"]
      )
        @model = model
        @python_bin = python_bin
      end

      def available?
        _stdout, _stderr, status = Open3.capture3(@python_bin, "-c", availability_probe)
        status.success?
      end

      def embed(text)
        unless available?
          raise ProviderError, "runtime_blocked_missing_local_model: install sentence-transformers or FlagEmbedding, then ensure #{model} is available locally"
        end

timeout_seconds = (ENV["PCO_BGE_TIMEOUT_SECONDS"] || "120").to_i
timeout_seconds = 120 unless timeout_seconds.positive?
stdout, stderr, status = capture_python_embedding(
  JSON.generate({ "model" => model, "text" => text.to_s }),
  timeout_seconds
)
raise ProviderError, "local BGE embedding failed: #{stderr.to_s.strip}" unless status.success?

        payload = JSON.parse(stdout)
        vector = payload.fetch("vector")
        raise ProviderError, "local BGE embedding returned empty vector" unless vector.is_a?(Array) && !vector.empty?

        {
          "provider" => "local_open_source_bge_small_zh",
          "model" => payload["model"] || model,
          "embedding_dim" => vector.length,
          "real_embedding_performed" => true,
          "provider_runtime" => payload["provider_runtime"],
          "vector" => vector
        }
      rescue JSON::ParserError => e
        raise ProviderError, "local BGE embedding response was not valid JSON: #{e.message}"
      end

      private

      def availability_probe
        <<~'PY'
          import importlib.util
          available = importlib.util.find_spec("sentence_transformers") or importlib.util.find_spec("FlagEmbedding")
          raise SystemExit(0 if available else 1)
        PY
      end

      def capture_python_embedding(stdin_payload, timeout_seconds)
  stdout = stderr = status = nil
  Open3.popen3(@python_bin, "-c", embedding_script) do |stdin, out, err, wait_thr|
    stdin.write(stdin_payload)
    stdin.close
    stdout_reader = Thread.new { out.read }
    stderr_reader = Thread.new { err.read }

    unless wait_thr.join(timeout_seconds)
      begin
        Process.kill("TERM", wait_thr.pid)
        sleep 1
        Process.kill("KILL", wait_thr.pid) if wait_thr.alive?
      rescue Errno::ESRCH
        # Process already exited.
      end
      raise ProviderError, "runtime_blocked_timeout: local BGE embedding did not finish within #{timeout_seconds}s"
    end

    stdout = stdout_reader.value
    stderr = stderr_reader.value
    status = wait_thr.value
  end
  [stdout, stderr, status]
end

def embedding_script
        <<~'PY'
          import json
          import sys

          payload = json.load(sys.stdin)
          model_name = payload.get("model") or "BAAI/bge-small-zh-v1.5"
          text = payload.get("text") or ""

          try:
              from sentence_transformers import SentenceTransformer
              model = SentenceTransformer(model_name)
              vector = model.encode([text], normalize_embeddings=True)[0].tolist()
              print(json.dumps({
                  "model": model_name,
                  "provider_runtime": "sentence_transformers",
                  "vector": vector
              }))
          except Exception as first_error:
              try:
                  from FlagEmbedding import FlagModel
                  model = FlagModel(model_name, use_fp16=False)
                  vector = model.encode([text], normalize_embeddings=True)[0].tolist()
                  print(json.dumps({
                      "model": model_name,
                      "provider_runtime": "FlagEmbedding",
                      "vector": vector
                  }))
              except Exception as second_error:
                  print(
                      json.dumps({
                          "error": f"sentence_transformers: {first_error}; FlagEmbedding: {second_error}"
                      }),
                      file=sys.stderr
                  )
                  raise SystemExit(2)
        PY
      end
    end

    def self.build(provider: ENV["PCO_EMBEDDING_PROVIDER"] || "local_open_source_bge_small_zh", **options)
      case provider.to_s
      when "local_open_source_bge_small_zh", "bge_small_zh", "bge"
        LocalOpenSourceBGESmallZH.new(**options)
      when "local_hash_dry_run", "dry_run", "smoke"
        LocalHashDryRun.new(**options)
      else
        raise ProviderError, "unknown embedding provider: #{provider}"
      end
    end
  end
end
