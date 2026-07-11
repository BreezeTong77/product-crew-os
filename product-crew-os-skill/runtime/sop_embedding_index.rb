require "yaml"
require_relative "embedding_provider"
require_relative "rag_store"

module ProductCrewOS
  class SopEmbeddingIndex
    attr_reader :provider

    def initialize(prompt_eval_path:, provider: ProductCrewOS::EmbeddingProviders.build, db_path: nil)
      @prompt_eval_path = prompt_eval_path
      @provider = provider
      @cases = load_cases(prompt_eval_path)
      @store = db_path.to_s.empty? ? nil : PersistentRagStore.new(db_path: db_path, provider: provider)
    end

    def retrieve(query, top_k: 3)
      return retrieve_from_persistent_store(query, top_k) if @store

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

    def retrieve_from_persistent_store(query, top_k)
      @store.upsert_documents(
        namespace: PersistentRagStore::DEFAULT_NAMESPACE,
        scope: PersistentRagStore::DEFAULT_SCOPE,
        documents: @cases.map do |entry|
          {
            source_ref: "tests/prompt-eval-cases.yaml##{entry.fetch("case_id")}",
            title: entry.fetch("stage_id"),
            content: case_search_text(entry),
            source_type: "yaml",
            extraction_method: "structured_yaml_parser",
            metadata: {
              "stage_id" => entry.fetch("stage_id"),
              "case_id" => entry.fetch("case_id"),
              "macro_stage" => entry.fetch("macro_stage", "")
            }
          }
        end
      )
      payload = @store.retrieve(
        query: query,
        namespace: PersistentRagStore::DEFAULT_NAMESPACE,
        top_k: top_k,
        allowed_scopes: [PersistentRagStore::DEFAULT_SCOPE],
        used_for: "sop_routing"
      )
      payload.merge(
        "candidates" => payload.fetch("candidates").map do |candidate|
          candidate.slice("stage_id", "case_id", "score", "vector_score", "matched_terms", "source_refs")
        end
      )
    end

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
