require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "time"
require_relative "embedding_provider"

module ProductCrewOS
  # Durable local-first vector store. Metadata and vectors live in the same
  # SQLite file as the Product Crew OS Runtime, so source_ref and consent
  # boundaries are enforceable during retrieval rather than only documented.
  class PersistentRagStore
    DEFAULT_NAMESPACE = "pco_rules".freeze
    DEFAULT_SCOPE = "product_rule_memory".freeze

    attr_reader :db_path, :provider

    def initialize(db_path:, provider: EmbeddingProviders.build)
      @db_path = File.expand_path(db_path)
      @provider = provider
      FileUtils.mkdir_p(File.dirname(@db_path)) unless Dir.exist?(File.dirname(@db_path))
      ensure_schema!
    end

    def upsert_documents(namespace:, scope:, documents:, consent_ref: "", public_package_allowed: nil, batch_id: nil)
      validate_namespace!(namespace, scope, consent_ref)
      batch_id ||= "batch_#{SecureRandom.hex(8)}"
      candidates = Array(documents).map { |document| normalize_document(document, namespace, scope, consent_ref, public_package_allowed) }
      changed = candidates.reject { |document| unchanged?(document) }
      return { "batch_id" => batch_id, "created" => 0, "updated" => 0, "skipped" => candidates.length, "vector_store" => vector_store_name } if changed.empty?

      chunks_by_document = changed.to_h { |document| [document.fetch("doc_id"), semantic_chunks(document)] }
      embeddings = provider.embed_batch(chunks_by_document.values.flatten.map { |chunk| chunk.fetch("text") })
      cursor = 0
      now = timestamp
      created = 0
      updated = 0

      changed.each do |document|
        existing = document_row(document.fetch("doc_id"))
        chunks = chunks_by_document.fetch(document.fetch("doc_id"))
        chunk_embeddings = embeddings.slice(cursor, chunks.length)
        cursor += chunks.length
        job_id = "ragjob_#{SecureRandom.hex(10)}"
        insert_job(job_id, document, batch_id, "running", now)
        begin
          sql = ["BEGIN;"]
          sql << upsert_document_sql(document, now)
          sql << "DELETE FROM embedding_chunks WHERE doc_id = #{q(document.fetch("doc_id"))};"
          chunks.zip(chunk_embeddings).each_with_index do |(chunk, embedding), index|
            sql << insert_chunk_sql(document, chunk.merge("chunk_index" => index), embedding, now)
          end
          sql << update_job_sql(job_id, "succeeded", chunks.length, now)
          sql << "COMMIT;"
          execute(sql.join("\n"))
          existing ? updated += 1 : created += 1
        rescue StandardError => error
          execute("ROLLBACK;") rescue nil
          update_failed_job(job_id, error.message)
          raise
        end
      end
      update_vector_index(changed, now)
      record_maintenance("index_upsert", namespace, changed.length, chunks_by_document.values.flatten.length, "succeeded", batch_id)
      {
        "batch_id" => batch_id,
        "created" => created,
        "updated" => updated,
        "skipped" => candidates.length - changed.length,
        "vector_store" => vector_store_name,
        "provider" => provider_name,
        "model" => provider_model
      }
    end

    def retrieve(query:, namespace: DEFAULT_NAMESPACE, top_k: 3, allowed_scopes: nil, consent_ref: "", used_for: "sop_routing")
      validate_retrieval_scope!(namespace, consent_ref)
      query_embedding = provider.embed(query.to_s)
      rows = query(<<~SQL)
        SELECT d.scope, d.consent_ref, d.source_ref, d.title, c.chunk_id, c.text, c.section_path,
               c.metadata_json, c.vector_json, c.embedding_model
        FROM embedding_chunks c
        JOIN embedding_documents d ON d.doc_id = c.doc_id
        WHERE d.namespace = #{q(namespace)}
          AND d.deleted_at = ''
          AND c.deleted_at = ''
          AND c.stale = 0;
      SQL
      permitted = Array(allowed_scopes).map(&:to_s)
      candidates = rows.map do |row|
        next if !permitted.empty? && !permitted.include?(row.fetch("scope"))
        next if namespace.to_s != DEFAULT_NAMESPACE && row.fetch("consent_ref").to_s != consent_ref.to_s

        vector = JSON.parse(row.fetch("vector_json"))
        metadata = JSON.parse(row.fetch("metadata_json"))
        score = cosine(query_embedding.fetch("vector"), vector)
        {
          "score" => score.round(4),
          "vector_score" => score.round(4),
          "chunk_id" => row.fetch("chunk_id"),
          "stage_id" => metadata["stage_id"],
          "case_id" => metadata["case_id"],
          "source_ref" => row.fetch("source_ref"),
          "source_refs" => [row.fetch("source_ref")],
          "section_path" => row.fetch("section_path"),
          "matched_terms" => [],
          "text" => row.fetch("text")
        }
      rescue JSON::ParserError
        nil
      end.compact.sort_by { |candidate| [-candidate.fetch("vector_score"), candidate.fetch("source_ref")] }.first(top_k.to_i)
      write_retrieval_event(query, namespace, query_embedding, candidates, used_for)
      {
        "provider" => query_embedding.fetch("provider"),
        "model" => query_embedding.fetch("model"),
        "embedding_dim" => query_embedding.fetch("embedding_dim"),
        "real_embedding_performed" => query_embedding.fetch("real_embedding_performed"),
        "provider_runtime" => query_embedding["provider_runtime"],
        "vector_store" => vector_store_name,
        "candidates" => candidates
      }
    end

    def stats(namespace: DEFAULT_NAMESPACE)
      document_count = query_value("SELECT COUNT(*) AS count FROM embedding_documents WHERE namespace = #{q(namespace)} AND deleted_at = '';").to_i
      chunk_count = query_value(<<~SQL).to_i
        SELECT COUNT(*) AS count FROM embedding_chunks c
        JOIN embedding_documents d ON d.doc_id = c.doc_id
        WHERE d.namespace = #{q(namespace)} AND d.deleted_at = '' AND c.deleted_at = '' AND c.stale = 0;
      SQL
      { "namespace" => namespace, "documents" => document_count, "chunks" => chunk_count, "vector_store" => vector_store_name }
    end

    private

    def normalize_document(document, namespace, scope, consent_ref, public_package_allowed)
      value = stringify_keys(document)
      source_ref = value.fetch("source_ref").to_s
      content = value.fetch("content").to_s
      raise "RAG source_ref is required" if source_ref.strip.empty?
      raise "RAG content is required" if content.strip.empty?

      {
        "doc_id" => "ragdoc_#{Digest::SHA256.hexdigest("#{namespace}|#{source_ref}")[0, 24]}",
        "namespace" => namespace,
        "scope" => scope,
        "source_ref" => source_ref,
        "source_type" => value.fetch("source_type", "markdown"),
        "title" => value.fetch("title", source_ref),
        "content" => content,
        "content_hash" => Digest::SHA256.hexdigest(content),
        "consent_ref" => consent_ref,
        "public_package_allowed" => public_package_allowed.nil? ? namespace == DEFAULT_NAMESPACE : public_package_allowed,
        "extraction_method" => value.fetch("extraction_method", "direct_structured_parser"),
        "metadata" => value.fetch("metadata", {})
      }
    end

    def semantic_chunks(document)
      sections = structured_sections(document.fetch("content"), document.fetch("title"))
      chunks = []
      sections.each do |section|
        text = section.fetch("text").strip
        next if text.empty?

        split_text_with_overlap(text).each_with_index do |chunk_text, index|
          content_hash = Digest::SHA256.hexdigest(chunk_text)
          chunks << {
            "chunk_id" => "ragchunk_#{Digest::SHA256.hexdigest([document.fetch("namespace"), document.fetch("source_ref"), section.fetch("path"), content_hash].join("|"))[0, 24]}",
            "section_path" => section.fetch("path"),
            "text" => chunk_text,
            "content_hash" => content_hash,
            "metadata" => document.fetch("metadata").merge("chunk_sequence" => index, "source_title" => document.fetch("title"))
          }
        end
      end
      chunks
    end

    def structured_sections(content, title)
      sections = []
      heading = title
      buffer = []
      content.each_line do |line|
        if line.match?(/^\#{1,6}\s+/)
          sections << { "path" => heading, "text" => buffer.join } unless buffer.empty?
          heading = line.sub(/^\#{1,6}\s+/, "").strip
          buffer = []
        else
          buffer << line
        end
      end
      sections << { "path" => heading, "text" => buffer.join } unless buffer.empty?
      sections.empty? ? [{ "path" => title, "text" => content }] : sections
    end

    def split_text_with_overlap(text)
      max = 900
      overlap = 120
      paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
      chunks = []
      current = ""
      paragraphs.each do |paragraph|
        if current.empty? || current.length + paragraph.length + 2 <= max
          current = [current, paragraph].reject(&:empty?).join("\n\n")
          next
        end
        chunks << current
        current = "#{current[-overlap, overlap]}\n\n#{paragraph}"
      end
      chunks << current unless current.empty?
      chunks
    end

    def unchanged?(document)
      existing = document_row(document.fetch("doc_id"))
      existing && existing["content_hash"].to_s == document.fetch("content_hash") && existing["deleted_at"].to_s.empty?
    end

    def document_row(doc_id)
      query("SELECT * FROM embedding_documents WHERE doc_id = #{q(doc_id)} LIMIT 1;").first
    end

    def upsert_document_sql(document, now)
      <<~SQL
        INSERT INTO embedding_documents
          (doc_id, namespace, scope, source_type, source_ref, owner, title, extraction_method, extraction_confidence, content_hash, pii_level, consent_ref, public_package_allowed, indexed_at, deleted_at, created_at, updated_at)
        VALUES
          (#{q(document.fetch("doc_id"))}, #{q(document.fetch("namespace"))}, #{q(document.fetch("scope"))}, #{q(document.fetch("source_type"))}, #{q(document.fetch("source_ref"))}, 'Product Crew OS', #{q(document.fetch("title"))}, #{q(document.fetch("extraction_method"))}, 1.0, #{q(document.fetch("content_hash"))}, 'none', #{q(document.fetch("consent_ref"))}, #{document.fetch("public_package_allowed") ? 1 : 0}, #{q(now)}, '', #{q(now)}, #{q(now)})
        ON CONFLICT(doc_id) DO UPDATE SET
          namespace = excluded.namespace,
          scope = excluded.scope,
          source_type = excluded.source_type,
          source_ref = excluded.source_ref,
          title = excluded.title,
          extraction_method = excluded.extraction_method,
          content_hash = excluded.content_hash,
          consent_ref = excluded.consent_ref,
          public_package_allowed = excluded.public_package_allowed,
          indexed_at = excluded.indexed_at,
          deleted_at = '',
          updated_at = excluded.updated_at;
      SQL
    end

    def insert_chunk_sql(document, chunk, embedding, now)
      metadata = JSON.generate(chunk.fetch("metadata"))
      <<~SQL
        INSERT INTO embedding_chunks
          (chunk_id, doc_id, chunk_index, source_ref, section_path, parent_heading, chunk_strategy, text, metadata_json, source_type, extraction_method, token_count, char_count, embedding_provider, embedding_model, embedding_dim, vector_json, content_hash, stale, deleted_at, created_at, updated_at)
        VALUES
          (#{q(chunk.fetch("chunk_id"))}, #{q(document.fetch("doc_id"))}, #{chunk.fetch("chunk_index")}, #{q(document.fetch("source_ref"))}, #{q(chunk.fetch("section_path"))}, #{q(chunk.fetch("section_path"))}, 'semantic_structured_overlap', #{q(chunk.fetch("text"))}, #{q(metadata)}, #{q(document.fetch("source_type"))}, #{q(document.fetch("extraction_method"))}, 0, #{chunk.fetch("text").length}, #{q(embedding.fetch("provider"))}, #{q(embedding.fetch("model"))}, #{embedding.fetch("embedding_dim")}, #{q(JSON.generate(embedding.fetch("vector")))}, #{q(chunk.fetch("content_hash"))}, 0, '', #{q(now)}, #{q(now)});
      SQL
    end

    def insert_job(job_id, document, batch_id, status, now)
      execute(<<~SQL)
        INSERT INTO rag_ingestion_jobs
          (job_id, namespace, scope, source_ref, source_type, extraction_method, status, batch_id, idempotency_key, content_hash_after, started_at, created_at, updated_at)
        VALUES
          (#{q(job_id)}, #{q(document.fetch("namespace"))}, #{q(document.fetch("scope"))}, #{q(document.fetch("source_ref"))}, #{q(document.fetch("source_type"))}, #{q(document.fetch("extraction_method"))}, #{q(status)}, #{q(batch_id)}, #{q(Digest::SHA256.hexdigest("#{document.fetch("source_ref")}|#{document.fetch("content_hash")}|#{provider_model}"))}, #{q(document.fetch("content_hash"))}, #{q(now)}, #{q(now)}, #{q(now)});
      SQL
    end

    def update_job_sql(job_id, status, chunk_count, now)
      "UPDATE rag_ingestion_jobs SET status = #{q(status)}, chunks_created = #{chunk_count}, finished_at = #{q(now)}, updated_at = #{q(now)} WHERE job_id = #{q(job_id)};"
    end

    def update_failed_job(job_id, message)
      execute("UPDATE rag_ingestion_jobs SET status = 'failed', error_message = #{q(message)}, finished_at = #{q(timestamp)}, updated_at = #{q(timestamp)} WHERE job_id = #{q(job_id)};")
    end

    def update_vector_index(documents, now)
      namespace = documents.first.fetch("namespace")
      count = query_value(<<~SQL).to_i
        SELECT COUNT(*) AS count FROM embedding_chunks c
        JOIN embedding_documents d ON d.doc_id = c.doc_id
        WHERE d.namespace = #{q(namespace)} AND d.deleted_at = '' AND c.deleted_at = '' AND c.stale = 0;
      SQL
      execute(<<~SQL)
        INSERT INTO embedding_vector_indexes
          (vector_index_id, engine, vector_table, embedding_model, embedding_dim, distance, source_chunk_count, last_rebuild_at, created_at, updated_at)
        VALUES
          (#{q("#{namespace}_default")}, #{q(vector_store_name)}, 'embedding_chunks.vector_json', #{q(provider_model)}, 512, 'cosine', #{count}, #{q(now)}, #{q(now)}, #{q(now)})
        ON CONFLICT(vector_index_id) DO UPDATE SET
          engine = excluded.engine,
          embedding_model = excluded.embedding_model,
          source_chunk_count = excluded.source_chunk_count,
          last_rebuild_at = excluded.last_rebuild_at,
          updated_at = excluded.updated_at;
      SQL
    end

    def write_retrieval_event(query_text, namespace, embedding, candidates, used_for)
      now = timestamp
      execute(<<~SQL)
        INSERT INTO embedding_retrieval_events
          (query_id, namespace, query_text_hash, retrieval_mode, provider, vector_store, embedding_model, top_k, top_candidates_json, score_breakdown_json, selected_stage, selected_sop, confidence, confidence_gap, used_for, source_refs_json, created_at)
        VALUES
          (#{q("ragquery_#{SecureRandom.hex(10)}")}, #{q(namespace)}, #{q(Digest::SHA256.hexdigest(query_text.to_s))}, #{q("persistent_embedding_rag")}, #{q(embedding.fetch("provider"))}, #{q(vector_store_name)}, #{q(embedding.fetch("model"))}, #{candidates.length}, #{q(JSON.generate(candidates))}, #{q(JSON.generate(candidates.map { |candidate| { source_ref: candidate["source_ref"], vector_score: candidate["vector_score"] } }))}, #{q(candidates.first&.fetch("stage_id", "").to_s)}, #{q(candidates.first&.fetch("case_id", "").to_s)}, #{candidates.first ? candidates.first.fetch("score") : 0}, #{confidence_gap(candidates)}, #{q(used_for)}, #{q(JSON.generate(candidates.flat_map { |candidate| candidate.fetch("source_refs") }.uniq))}, #{q(now)});
      SQL
    end

    def record_maintenance(event_type, namespace, source_count, chunk_count, status, details)
      execute(<<~SQL)
        INSERT INTO rag_maintenance_events
          (maintenance_id, event_type, namespace, affected_sources, affected_chunks, status, details_json, created_at)
        VALUES
          (#{q("ragmaint_#{SecureRandom.hex(10)}")}, #{q(event_type)}, #{q(namespace)}, #{source_count}, #{chunk_count}, #{q(status)}, #{q(JSON.generate({ details: details }))}, #{q(timestamp)});
      SQL
    end

    def ensure_schema!
      schema_path = File.expand_path("db/embedding-rag-schema.sql", __dir__)
      execute(File.read(schema_path))
    end

    def execute(sql)
      _stdout, stderr, status = Open3.capture3("sqlite3", "-cmd", ".timeout 5000", @db_path, stdin_data: sql)
      raise "RAG SQLite write failed: #{stderr.strip}" unless status.success?
    end

    def query(sql)
      stdout, stderr, status = Open3.capture3("sqlite3", "-cmd", ".timeout 5000", "-json", @db_path, sql)
      raise "RAG SQLite query failed: #{stderr.strip}" unless status.success?

      stdout.strip.empty? ? [] : JSON.parse(stdout)
    end

    def query_value(sql)
      query(sql).first&.fetch("count", nil)
    end

    def validate_namespace!(namespace, scope, consent_ref)
      return if namespace.to_s == DEFAULT_NAMESPACE && scope.to_s == DEFAULT_SCOPE
      raise "private RAG namespace requires consent_ref" if consent_ref.to_s.strip.empty?
    end

    def validate_retrieval_scope!(namespace, consent_ref)
      return if namespace.to_s == DEFAULT_NAMESPACE
      raise "private RAG retrieval requires consent_ref" if consent_ref.to_s.strip.empty?
    end

    def provider_name
      provider.respond_to?(:model) ? provider.class.name.split("::").last : "unknown"
    end

    def provider_model
      provider.respond_to?(:model) ? provider.model.to_s : "unknown"
    end

    def vector_store_name
      "sqlite_json_cosine_fallback"
    end

    def cosine(left, right)
      numerator = left.zip(right).sum { |a, b| a.to_f * b.to_f }
      left_norm = Math.sqrt(left.sum { |value| value.to_f * value.to_f })
      right_norm = Math.sqrt(right.sum { |value| value.to_f * value.to_f })
      return 0.0 if left_norm.zero? || right_norm.zero?

      numerator / (left_norm * right_norm)
    end

    def confidence_gap(candidates)
      return 0.0 if candidates.length < 2

      (candidates[0].fetch("score") - candidates[1].fetch("score")).round(4)
    end

    def stringify_keys(value)
      return value.map { |item| stringify_keys(item) } if value.is_a?(Array)
      return value unless value.is_a?(Hash)

      value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify_keys(item) }
    end

    def q(value)
      "'#{value.to_s.gsub("'", "''")}'"
    end

    def timestamp
      Time.now.utc.iso8601
    end
  end
end
