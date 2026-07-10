require "yaml"
require_relative "embedding_provider"

module ProductCrewOS
  class SopEmbeddingIndex
    attr_reader :provider

    def initialize(prompt_eval_path:, provider: ProductCrewOS::EmbeddingProviders.build)
      @prompt_eval_path = prompt_eval_path
      @provider = provider
      @cases = load_cases(prompt_eval_path)
    end

    def retrieve(query, top_k: 3)
      texts = [query.to_s] + @cases.map { |entry| case_search_text(entry) }
      embeddings = @provider.embed_batch(texts)
      query_embedding = embeddings.first
      query_vector = query_embedding.fetch("vector")
      rows = @cases.zip(embeddings.drop(1)).map do |entry, embedding|
        vector_score = cosine(query_vector, embedding.fetch("vector"))
        {
          "stage_id" => entry.fetch("stage_id"),
          "case_id" => entry.fetch("case_id"),
          "score" => vector_score.round(3),
          "vector_score" => vector_score.round(3),
          "matched_terms" => [],
          "source_refs" => ["tests/prompt-eval-cases.yaml##{entry.fetch("case_id")}"]
        }
      end

      {
        "provider" => query_embedding.fetch("provider"),
        "model" => query_embedding.fetch("model"),
        "embedding_dim" => query_embedding.fetch("embedding_dim"),
        "real_embedding_performed" => query_embedding.fetch("real_embedding_performed"),
        "provider_runtime" => query_embedding["provider_runtime"],
        "candidates" => rows.sort_by { |row| [-row.fetch("vector_score"), row.fetch("stage_id")] }.first(top_k)
      }
    end

    private

    def load_cases(path)
      return [] unless File.exist?(path)

      YAML.load_file(path).fetch("cases")
    end

    def case_search_text(entry)
      expected = entry["expected"] || {}
      [
        entry["case_id"],
        entry["stage_id"],
        entry["macro_stage"],
        entry["user_input"],
        expected["primary_skill"],
        expected["fallback_skill"],
        Array(expected["required_roles"]).join(" "),
        Array(expected["triggered_roles"]).join(" "),
        Array(expected["required_artifacts"]).join(" "),
        expected["stage_gate"]
      ].compact.join(" ")
    end

    def cosine(left, right)
      numerator = left.zip(right).sum { |a, b| a.to_f * b.to_f }
      left_norm = Math.sqrt(left.sum { |value| value.to_f * value.to_f })
      right_norm = Math.sqrt(right.sum { |value| value.to_f * value.to_f })
      return 0.0 if left_norm.zero? || right_norm.zero?

      numerator / (left_norm * right_norm)
    end
  end
end
