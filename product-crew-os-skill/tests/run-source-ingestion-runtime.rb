#!/usr/bin/env ruby

require "base64"
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "runtime"))
require "embedding_provider"
require "rag_store"
require "source_extractor"

def assert(errors, condition, message)
  errors << message unless condition
end

def rows(db, sql)
  stdout, stderr, status = Open3.capture3("sqlite3", "-json", db, sql)
  raise "sqlite query failed: #{stderr}" unless status.success?

  stdout.strip.empty? ? [] : JSON.parse(stdout)
end

errors = []
ocr_runtime_status = "not_checked"

Dir.mktmpdir("pco-source-ingestion-") do |dir|
  db = File.join(dir, "pco.sqlite3")
  markdown_path = File.join(dir, "source.md")
  image_path = File.join(dir, "source.png")
  File.write(markdown_path, "# 需求证据\n\n审核工作台需要来源可追溯。\n")
  File.binwrite(image_path, Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL7NwAAAABJRU5ErkJggg=="))

  extractor = ProductCrewOS::SourceExtractor.new
  structured = extractor.extract(file_path: markdown_path, source_ref: "fixture:structured", source_type: "markdown")
  assert(errors, structured["content"].include?("需求证据"), "structured source did not return source text")
  assert(errors, structured["extraction_method"] == "direct_structured_parser", "structured source extraction method is not explicit")
  assert(errors, structured["extraction_confidence"] == 1.0, "exact structured parsing should record its exact extraction confidence")
  assert(errors, structured["source_hash"].to_s.length == 64, "structured source did not record a source hash")

  smoke_source = ENV.fetch("PCO_OCR_SMOKE_SOURCE", "").to_s.strip
  if !smoke_source.empty?
    real_ocr = extractor.extract(file_path: smoke_source, source_ref: "fixture:real-ocr-smoke", source_type: "screenshot")
    assert(errors, real_ocr.fetch("content").length >= 20, "real OCR smoke returned too little text")
    assert(errors, real_ocr.fetch("ocr_confidence").to_f >= ProductCrewOS::SourceExtractor::OCR_THRESHOLD, "real OCR smoke did not reach the configured confidence threshold")
    assert(errors, real_ocr["gate_evidence_eligible"] == true, "real OCR smoke was not gate-evidence eligible")
    ocr_runtime_status = "real_local_ocr_passed"
  elsif !extractor.capability.values_at("paddleocr", "tesseract").any?
    begin
      extractor.extract(file_path: image_path, source_ref: "fixture:image", source_type: "image")
      errors << "blank image was accepted as OCR evidence"
    rescue ProductCrewOS::SourceExtractor::RuntimeBlocked => error
      ocr_runtime_status = error.message
      assert(errors, error.message.include?("runtime_blocked"), "missing OCR engine did not return a runtime_blocked status")
    end
  else
    ocr_runtime_status = "engine_available_real_smoke_source_not_provided"
  end

  store = ProductCrewOS::PersistentRagStore.new(
    db_path: db,
    provider: ProductCrewOS::EmbeddingProviders::LocalHashDryRun.new
  )
  structured_result = store.upsert_documents(
    namespace: "pco_rules",
    scope: "product_rule_memory",
    documents: [{
      source_ref: "fixture:structured-yaml",
      title: "Structured YAML",
      content: "stage: mvp_scope\nartifact: scope\n",
      source_type: "yaml",
      extraction_method: "structured_yaml_parser"
    }]
  )
  assert(errors, structured_result["created"] == 1, "structured YAML parser was incorrectly rejected")

  store.upsert_documents(
    namespace: "project_ocr_test",
    scope: "project_memory",
    consent_ref: "consent:source-runtime-test",
    documents: [{
      source_ref: "fixture:low-confidence-ocr",
      title: "Low Confidence OCR",
      content: "审核工作台截图文字",
      source_type: "screenshot",
      extraction_method: "ocr",
      metadata: {
        "source_uri_hash" => "fixture-hash",
        "extraction_confidence" => 0.61,
        "ocr_engine" => "fixture_ocr_for_parser_test",
        "ocr_confidence" => 0.61,
        "ocr_page_index" => 0,
        "ocr_bbox_json" => { "words" => [] },
        "pii_level" => "normal"
      }
    }]
  )
  stored = rows(db, "SELECT extraction_confidence, pii_level FROM embedding_documents WHERE source_ref = 'fixture:low-confidence-ocr';").first
  assert(errors, stored["extraction_confidence"].to_f == 0.61, "OCR extraction confidence was overwritten")
  assert(errors, stored["pii_level"] == "normal", "PII level was overwritten")

  retrieved = store.retrieve(
    query: "审核工作台截图",
    namespace: "project_ocr_test",
    allowed_scopes: ["project_memory"],
    consent_ref: "consent:source-runtime-test"
  )
  candidate = retrieved.fetch("candidates").find { |item| item["source_ref"] == "fixture:low-confidence-ocr" }
  assert(errors, candidate && candidate["gate_evidence_eligible"] == false, "low-confidence OCR was marked gate eligible")
  assert(errors, candidate && candidate["gate_evidence_reason"] == "extraction_confidence_below_threshold", "low-confidence OCR did not expose its rejection reason")

  evidence = store.evidence_status(source_refs: ["fixture:low-confidence-ocr", "fixture:not-indexed"])
  low_confidence = evidence.find { |item| item["source_ref"] == "fixture:low-confidence-ocr" }
  missing = evidence.find { |item| item["source_ref"] == "fixture:not-indexed" }
  assert(errors, low_confidence && low_confidence["gate_evidence_eligible"] == false, "low-confidence OCR evidence status was gate eligible")
  assert(errors, missing && missing["reason"] == "source_not_indexed", "missing source_ref was accepted as evidence")
end

if errors.empty?
  puts "run-source-ingestion-runtime: PASS"
  puts "ocr_runtime_status: #{ocr_runtime_status}"
else
  warn "run-source-ingestion-runtime: FAIL"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
