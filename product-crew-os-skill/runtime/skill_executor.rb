require "digest"
require "json"
require "net/http"
require "open3"
require "time"
require "uri"
require "yaml"

# Executes only explicitly registered, argument-safe Skill drivers. It never
# treats a SKILL.md file as executable code and never invokes a shell.
class ProductCrewSkillExecutor
  def initialize(skill_root:)
    @skill_root = File.expand_path(skill_root)
    config = YAML.load_file(File.join(@skill_root, "config", "skill-executor-registry.yaml"))
    @registry = config.fetch("skills")
    @defaults = config.fetch("defaults", {})
    @bundled_index = File.read(File.join(@skill_root, "references", "bundled-skill-index.md")).scan(/^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`/).to_h
  end

  def execute(skill_id:, input:)
    entry = @registry[skill_id.to_s] || implicit_ollama_entry(skill_id.to_s)
    return unavailable(skill_id, "skill_not_registered_for_execution") unless entry

    case entry.fetch("driver")
    when "command"
      execute_command(skill_id.to_s, entry, stringify_keys(input))
    when "ollama_prompt"
      execute_ollama_prompt(skill_id.to_s, entry, stringify_keys(input))
    when "host_callback_required", "mcp_required", "missing_capability"
      deployment_required(skill_id, entry.fetch("driver"), entry.fetch("reason", ""), entry["deployment_notice"] || {})
    else
      unavailable(skill_id, "unknown_driver")
    end
  end

  private

  def execute_command(skill_id, entry, input)
    script = File.join(@skill_root, entry.fetch("source"))
    return unavailable(skill_id, "driver_source_missing") unless File.file?(script)

    command = ["python3", script, *command_arguments(entry.fetch("input_schema"), input)]
    stdout, stderr, status = Open3.capture3(*command)
    payload = {
      "skill_id" => skill_id,
      "driver" => "command",
      "execution_status" => status.success? ? "executed" : "failed",
      "output_type" => entry.fetch("output_type"),
      "stdout" => stdout,
      "stderr" => stderr,
      "execution_proof" => {
        "driver_source" => entry.fetch("source"),
        "command_sha256" => Digest::SHA256.hexdigest(command.join("\u0000")),
        "executed_at" => Time.now.utc.iso8601,
        "exit_code" => status.exitstatus
      }
    }
    payload
  rescue ArgumentError => error
    unavailable(skill_id, "invalid_input: #{error.message}")
  end

  def execute_ollama_prompt(skill_id, entry, input)
    model = ENV.fetch("PCO_SKILL_OLLAMA_MODEL", entry.fetch("model", @defaults.fetch("ollama_model", "qwen2.5:3b")))
    unless ollama_model_available?(model)
      return execute_deepseek_prompt(skill_id, entry, input) if deepseek_key_configured?

      return deployment_required(
        skill_id,
        "ollama_prompt",
        "Local model #{model} is not available.",
        {
          "title" => "需要部署本地 Ollama 模型",
          "user_message" => "该 Skill 可由本地 Ollama 或 DeepSeek API 真实执行，但当前未找到本地模型 #{model}，也没有配置当前进程可用的 DEEPSEEK_API_KEY。完成部署前系统不会把它标为已执行。",
          "required_steps" => ["启动 Ollama 并下载：ollama pull #{model}，或配置 DEEPSEEK_API_KEY", "重新执行该 Skill", "将输出交给 Product Crew OS 评审和 Gate"],
          "authorization_required" => false
        }
      )
    end

    source = entry.fetch("source")
    skill_path = File.join(@skill_root, source, "SKILL.md")
    return unavailable(skill_id, "skill_instruction_missing") unless File.file?(skill_path)

    prompt = build_skill_prompt(skill_id, skill_path, input)
    stdout, stderr, status = Open3.capture3("ollama", "run", model, prompt)
    {
      "skill_id" => skill_id,
      "driver" => "ollama_prompt",
      "execution_status" => status.success? ? "executed" : "failed",
      "output_type" => "markdown_draft",
      "stdout" => stdout,
      "stderr" => stderr,
      "execution_proof" => {
        "driver_source" => File.join(source, "SKILL.md"),
        "model" => model,
        "prompt_sha256" => Digest::SHA256.hexdigest(prompt),
        "executed_at" => Time.now.utc.iso8601,
        "exit_code" => status.exitstatus
      }
    }
  end

  def execute_deepseek_prompt(skill_id, entry, input)
    source = entry.fetch("source")
    skill_path = File.join(@skill_root, source, "SKILL.md")
    return unavailable(skill_id, "skill_instruction_missing") unless File.file?(skill_path)

    prompt = build_skill_prompt(skill_id, skill_path, input)
    model = ENV.fetch("PCO_SKILL_DEEPSEEK_MODEL", "deepseek-v4-flash")
    uri = URI(ENV.fetch("PCO_SKILL_DEEPSEEK_BASE_URL", "https://api.deepseek.com/chat/completions"))
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch("DEEPSEEK_API_KEY")}"
    request.body = JSON.generate(
      model: model,
      messages: [
        { role: "system", content: "You execute a bounded Product Crew OS Skill. Never claim a stage gate, persist memory, call an agent, or write external tools." },
        { role: "user", content: prompt }
      ],
      stream: false
    )
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 120) { |http| http.request(request) }
    parsed = JSON.parse(response.body)
    content = parsed.dig("choices", 0, "message", "content").to_s
    success = response.is_a?(Net::HTTPSuccess) && !content.empty?
    {
      "skill_id" => skill_id,
      "driver" => "deepseek_prompt",
      "execution_status" => success ? "executed" : "failed",
      "output_type" => "markdown_draft",
      "stdout" => content,
      "stderr" => success ? "" : "DeepSeek request failed with HTTP #{response.code}",
      "execution_proof" => {
        "driver_source" => File.join(source, "SKILL.md"),
        "model" => model,
        "provider" => "deepseek",
        "prompt_sha256" => Digest::SHA256.hexdigest(prompt),
        "executed_at" => Time.now.utc.iso8601,
        "http_status" => response.code.to_i,
        "provider_request_id" => response["x-request-id"].to_s
      }
    }
  rescue JSON::ParserError, SocketError, Net::OpenTimeout, Net::ReadTimeout => error
    {
      "skill_id" => skill_id,
      "driver" => "deepseek_prompt",
      "execution_status" => "failed",
      "stderr" => "DeepSeek execution failed: #{error.class}",
      "execution_proof" => nil
    }
  end

  def command_arguments(schema, input)
    case schema
    when "assumption_list"
      assumptions = Array(input["assumptions"])
      raise ArgumentError, "assumptions is required" if assumptions.empty?

      assumptions.flat_map do |assumption|
        item = stringify_keys(assumption)
        %w[statement category risk certainty].each { |key| raise ArgumentError, "assumption.#{key} is required" if item[key].to_s.strip.empty? }
        ["--assumption", [item["statement"], item["category"], item["risk"], item["certainty"]].join("|")]
      end
    when "experiment_sample_size"
      baseline = input["baseline"].to_s
      mde_absolute = input["mde_absolute"].to_s
      raise ArgumentError, "baseline is required" if baseline.empty?
      raise ArgumentError, "mde_absolute is required" if mde_absolute.empty?

      args = ["--baseline", baseline, "--mde-absolute", mde_absolute]
      args += ["--power", input["power"].to_s] unless input["power"].to_s.empty?
      args += ["--daily-eligible-users", input["daily_eligible_users"].to_s] unless input["daily_eligible_users"].to_s.empty?
      args
    else
      raise ArgumentError, "unsupported input schema: #{schema}"
    end
  end

  def unavailable(skill_id, reason, detail = "")
    {
      "skill_id" => skill_id,
      "execution_status" => "unavailable",
      "reason" => reason,
      "detail" => detail,
      "execution_proof" => nil
    }
  end

  def deployment_required(skill_id, driver, detail, notice)
    {
      "skill_id" => skill_id,
      "execution_status" => "deployment_required",
      "reason" => driver,
      "detail" => detail,
      "must_notify_user" => true,
      "deployment_notice" => {
        "title" => notice["title"].to_s,
        "user_message" => notice["user_message"].to_s,
        "required_steps" => Array(notice["required_steps"]),
        "authorization_required" => notice["authorization_required"] == true
      },
      "execution_proof" => nil
    }
  end

  def implicit_ollama_entry(skill_id)
    source = @bundled_index[skill_id]
    return nil unless source && File.file?(File.join(@skill_root, source, "SKILL.md"))

    { "driver" => "ollama_prompt", "source" => source }
  end

  def build_skill_prompt(skill_id, skill_path, input)
    skill_text = File.read(skill_path)
    <<~PROMPT
      你正在作为 Product Crew OS 的受控外部 Skill 执行器运行 `#{skill_id}`。

      严格遵循以下 Skill 指令完成专业工作，但不得自行改变产品阶段、决定 Stage Gate、写项目记忆、召唤子 Agent 或调用外部工具。请只返回中文 Markdown 产物草稿、关键假设和待验证项。

      ## Skill 指令

      #{skill_text[0, @defaults.fetch("prompt_max_chars", 24_000).to_i]}

      ## 结构化输入

      #{JSON.pretty_generate(input)}
    PROMPT
  end

  def deepseek_key_configured?
    !ENV.fetch("DEEPSEEK_API_KEY", "").strip.empty?
  end

  def ollama_model_available?(model)
    stdout, _stderr, status = Open3.capture3("ollama", "list")
    status.success? && stdout.lines.drop(1).any? { |line| line.split.first == model }
  end

  def stringify_keys(value)
    value.each_with_object({}) { |(key, item), result| result[key.to_s] = item } if value.is_a?(Hash)
  end
end
