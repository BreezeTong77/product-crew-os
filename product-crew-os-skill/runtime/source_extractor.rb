require "digest"
require "json"
require "open3"
require "time"

module ProductCrewOS
  # Extracts source text before RAG indexing. It deliberately refuses to turn
  # a missing OCR runtime into an apparently successful text extraction.
  class SourceExtractor
    class ExtractionError < StandardError; end
    class RuntimeBlocked < ExtractionError; end

    IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .webp .bmp .tif .tiff].freeze
    TEXT_EXTENSIONS = %w[.md .markdown .txt .yaml .yml .json].freeze
    OCR_THRESHOLD = 0.72

    def initialize(python_bin: self.class.default_python_bin, tesseract_bin: ENV.fetch("PCO_TESSERACT_BIN", "tesseract"))
      @python_bin = python_bin
      @tesseract_bin = tesseract_bin
    end

    def self.default_python_bin
      configured = ENV.fetch("PCO_OCR_PYTHON", "").to_s.strip
      return configured unless configured.empty?

      deployed = File.expand_path("~/.local/share/product-crew-os/ocr-env/bin/python")
      File.executable?(deployed) ? deployed : "python3"
    end

    def extract(file_path:, source_ref:, source_type: "auto", language_hint: "chi_sim+eng")
      path = File.expand_path(file_path.to_s)
      raise ExtractionError, "source file does not exist: #{path}" unless File.file?(path)

      resolved_type = source_type.to_s == "auto" ? infer_source_type(path) : source_type.to_s
      base = source_metadata(path, source_ref, resolved_type)
      case resolved_type
      when "markdown", "yaml", "json", "text"
        text = File.read(path, encoding: "UTF-8")
        raise ExtractionError, "source file is empty: #{path}" if text.strip.empty?

        base.merge(
          "content" => text,
          "extraction_method" => "direct_structured_parser",
          "extraction_confidence" => 1.0,
          "ocr_engine" => "",
          "ocr_confidence" => nil,
          "ocr_page_index" => -1,
          "ocr_bbox_json" => {}
        )
      when "screenshot", "image"
        extract_image_ocr(path, language_hint, base)
      else
        raise RuntimeBlocked, "runtime_blocked_source_type_not_implemented: #{resolved_type}; supply extracted content or deploy a matching parser"
      end
    end

    def capability
      {
        "paddleocr" => paddle_available?,
        "tesseract" => tesseract_available?,
        "supported_source_types" => %w[markdown yaml json text screenshot image],
        "ocr_threshold" => OCR_THRESHOLD
      }
    end

    private

    def infer_source_type(path)
      extension = File.extname(path).downcase
      return "screenshot" if IMAGE_EXTENSIONS.include?(extension)
      return "markdown" if %w[.md .markdown].include?(extension)
      return "yaml" if %w[.yaml .yml].include?(extension)
      return "json" if extension == ".json"
      return "text" if extension == ".txt"

      "unknown"
    end

    def source_metadata(path, source_ref, source_type)
      stat = File.stat(path)
      {
        "source_ref" => source_ref,
        "source_type" => source_type,
        "source_hash" => Digest::SHA256.file(path).hexdigest,
        "source_uri_hash" => Digest::SHA256.hexdigest(source_ref.to_s),
        "source_mtime" => stat.mtime.utc.iso8601,
        "source_path_basename" => File.basename(path)
      }
    end

    def extract_image_ocr(path, language_hint, base)
      result = paddle_extract(path, language_hint) if paddle_available?
      result ||= tesseract_extract(path, language_hint) if tesseract_available?
      raise RuntimeBlocked, "runtime_blocked_missing_ocr_engine: install PaddleOCR or Tesseract with requested language data" unless result
      raise ExtractionError, "OCR returned empty text" if result.fetch("content").to_s.strip.empty?

      confidence = result.fetch("ocr_confidence").to_f
      result.merge(base).merge(
        "extraction_method" => "ocr",
        "extraction_confidence" => confidence,
        "gate_evidence_eligible" => confidence >= OCR_THRESHOLD,
        "gate_evidence_reason" => confidence >= OCR_THRESHOLD ? "ocr_confidence_sufficient" : "ocr_confidence_below_threshold"
      )
    end

    def paddle_available?
      _stdout, _stderr, status = Open3.capture3(@python_bin, "-c", "import paddleocr")
      status.success?
    rescue Errno::ENOENT
      false
    end

    def tesseract_available?
      _stdout, _stderr, status = Open3.capture3(@tesseract_bin, "--version")
      status.success?
    rescue Errno::ENOENT
      false
    end

    # PaddleOCR 2.x exposes ocr(); 3.x exposes predict(). Keep both real
    # code paths, but do not silently accept an unparseable provider response.
    def paddle_extract(path, language_hint)
      payload = JSON.generate("path" => path, "language_hint" => language_hint)
      stdout, stderr, status = Open3.capture3(@python_bin, "-c", paddle_script, stdin_data: payload)
      raise ExtractionError, "PaddleOCR failed: #{stderr.strip}" unless status.success?

      # Some Paddle model loaders emit transport diagnostics before the final
      # one-line JSON payload. The OCR result is still real, so parse only the
      # final JSON record rather than treating provider logging as OCR text.
      json_payload = stdout.each_line.reverse_each.find { |line| line.strip.start_with?("{") }
      raise ExtractionError, "PaddleOCR returned no JSON payload: #{stderr.strip}" if json_payload.nil?
      parsed = JSON.parse(json_payload)
      raise ExtractionError, "PaddleOCR returned no text" if parsed.fetch("content", "").strip.empty?

      parsed.merge("ocr_engine" => "PaddleOCR")
    rescue JSON::ParserError => error
      raise ExtractionError, "PaddleOCR response was not valid JSON: #{error.message}"
    end

    def tesseract_extract(path, language_hint)
      languages = tesseract_languages
      required = language_hint.to_s.split("+").reject(&:empty?)
      missing = required.reject { |language| languages.include?(language) }
      unless missing.empty?
        raise RuntimeBlocked, "runtime_blocked_tesseract_language_missing: #{missing.join(",")}; installed=#{languages.join(",")}"
      end

      stdout, stderr, status = Open3.capture3(@tesseract_bin, path, "stdout", "-l", language_hint, "--psm", "6", "tsv")
      raise ExtractionError, "Tesseract failed: #{stderr.strip}" unless status.success?

      rows = stdout.each_line.drop(1).map { |line| line.strip.split("\t", 12) }.select { |row| row.length == 12 && row[11].to_s.strip != "" }
      words = rows.filter_map do |row|
        confidence = Float(row[10]) rescue nil
        next if confidence.nil? || confidence.negative?

        {
          "text" => row[11].strip,
          "confidence" => confidence / 100.0,
          "bbox" => { "x" => row[6].to_i, "y" => row[7].to_i, "width" => row[8].to_i, "height" => row[9].to_i },
          "page_index" => row[1].to_i - 1
        }
      end
      raise ExtractionError, "Tesseract returned no recognized words" if words.empty?

      confidence = words.sum { |word| word.fetch("confidence") } / words.length
      {
        "content" => words.map { |word| word.fetch("text") }.join(" "),
        "ocr_engine" => "Tesseract #{tesseract_version}",
        "ocr_confidence" => confidence.round(4),
        "ocr_page_index" => words.first.fetch("page_index"),
        "ocr_bbox_json" => { "words" => words.map { |word| word.slice("text", "confidence", "bbox", "page_index") } },
        "language_hint" => language_hint
      }
    end

    def tesseract_languages
      stdout, _stderr, status = Open3.capture3(@tesseract_bin, "--list-langs")
      raise RuntimeBlocked, "runtime_blocked_missing_ocr_engine: Tesseract could not list languages" unless status.success?

      stdout.each_line.map(&:strip).reject { |line| line.empty? || line.start_with?("List of available") }
    end

    def tesseract_version
      stdout, _stderr, _status = Open3.capture3(@tesseract_bin, "--version")
      stdout.lines.first.to_s.strip
    end

    def paddle_script
      <<~'PY'
        import json
        import sys

        payload = json.load(sys.stdin)
        path = payload["path"]
        language_hint = payload.get("language_hint", "chi_sim+eng")
        paddle_lang = "ch" if "chi_sim" in language_hint else "en"
        from paddleocr import PaddleOCR

        def old_api():
            engine = PaddleOCR(use_angle_cls=True, lang=paddle_lang)
            result = engine.ocr(path, cls=True)
            words = []
            for page_index, page in enumerate(result or []):
                for line in page or []:
                    bbox, pair = line
                    text, confidence = pair
                    words.append({"text": text, "confidence": float(confidence), "bbox": bbox, "page_index": page_index})
            return words

        try:
            words = old_api()
        except Exception as old_error:
            try:
                engine = PaddleOCR(lang=paddle_lang)
                result = engine.predict(path)
                words = []
                for page_index, page in enumerate(result or []):
                    data = page.json if hasattr(page, "json") else page
                    if isinstance(data, str):
                        data = json.loads(data)
                    payload_data = data.get("res", data) if isinstance(data, dict) else {}
                    texts = payload_data.get("rec_texts", [])
                    scores = payload_data.get("rec_scores", [])
                    boxes = payload_data.get("rec_boxes", [])
                    for text, score, bbox in zip(texts, scores, boxes):
                        words.append({"text": str(text), "confidence": float(score), "bbox": bbox, "page_index": page_index})
            except Exception as new_error:
                print(json.dumps({"error": f"PaddleOCR old API: {old_error}; new API: {new_error}"}), file=sys.stderr)
                raise SystemExit(2)

        text = " ".join(item["text"].strip() for item in words if item["text"].strip())
        confidence = sum(item["confidence"] for item in words) / len(words) if words else 0.0
        print(json.dumps({
            "content": text,
            "ocr_confidence": confidence,
            "ocr_page_index": words[0]["page_index"] if words else -1,
            "ocr_bbox_json": {"words": words},
            "language_hint": language_hint
        }, ensure_ascii=False))
      PY
    end
  end
end
