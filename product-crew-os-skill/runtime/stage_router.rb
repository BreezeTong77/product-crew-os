require "json"
require "yaml"
require_relative "sop_embedding_index"

class SemanticStageRouter
  DOMAIN_EXIT_PATTERNS = [
    /天气|几点|现在时间|翻译一下|帮我算|闲聊|讲个笑话|做饭|旅游|机票|股票|汇率|新闻/,
    /\bweather\b|\btime\b|\btranslate\b|\bjoke\b|\brecipe\b|\bstock\b|\bexchange rate\b/
  ].freeze

  PRODUCT_SIGNALS = [
    /产品|需求|用户|客户|PRD|prd|MVP|mvp|原型|评审|上线|复盘|指标|埋点|灰度|验收|研发|设计|业务|项目|流程|痛点|访谈|调研|路线图|backlog|roadmap|feature|launch|postmortem/,
    /审核工作台|内容审核|内容安全|质量管控|质检|复核|待审队列|知识库|RAG|AI\s*辅助|辅助判定|人工修正|采纳率|审核员|政策依据|相似案例|模型迭代/,
    /Product Crew OS|SOP|skill|Stage|Agent|artifact|workflow|router|product|founder|investor|runway|retention|activation|enterprise|workspace|assistant|content moderation|review workbench|knowledge base/i
  ].freeze

  RETRIEVAL_STOP_TERMS = %w[
    帮我 我想 我有 我要 我们 一下 一个 一版 这个 那个 做个 做一 我做 帮我做
    整理 我整 我整理 帮我整 看下 我看 帮我看 怎么 如何 一下子 help please one
  ].freeze

  ROUTES = [
    ["research_plan", [/验证.*痛点.*访谈样本|验证.*痛点.*通过标准|设计访谈样本|设计.*样本.*通过标准/], 0.96],
    ["interview_synthesis", [/访谈记录.*提炼|访谈.*提炼共性|访谈.*分歧|十份用户访谈|记录很乱.*共性/], 0.96],
    ["formal_requirements_review", [/标准\s*SOP.*评审|按标准\s*SOP.*评审|正式需求评审|通过.*条件通过.*驳回/], 0.96],
    ["data_review", [/数据负责人评审|指标.*推荐逻辑.*数据负责人|指标.*推荐逻辑.*评审|数据评审/], 0.96],
    ["iteration_planning", [/下一版.*backlog|基于复盘和数据|下一版该做什么|迭代 backlog|形成迭代/], 0.96],
    ["value_sizing", [/daily .*fortune|fortune card|luck card|gimmicky|shareable moments|distract.*retention|whether we should do it/], 0.96],
    ["solution_exploration", [/founder.*AI product|market buzz|answer reliability|workspace memory|investor narrative|help me decide|4 weeks.*8-10 weeks/], 0.96],
    ["stakeholder_map", [/哪些人|找谁|谁能拍板|拍板人|干系人|stakeholder|RACI|权责|对齐对象/], 0.9],
    ["business_context", [/商业背景|商业论证|业务背景|续费|效率|ROI|战略|业务目标|business case|老板说.*提升/], 0.88],
    ["existing_workflow_mapping", [/现状流程|当前流程|业务流程|梳理现状|as-is|流程是|手动同步|工作流映射/], 0.88],
    ["evidence_inventory", [/客户原话|截图|数据和销售反馈|事实.*假设|证据|材料|来源|缺口|evidence inventory/], 0.88],
    ["problem_definition", [/痛点|真需求|问题定义|怀疑.*需求|problem|用户问题|对不对|导出功能.*真/], 0.9],
    ["user_segmentation", [/用户分层|用户画像|先服务|新手PM|独立PM|团队负责人|segmentation|目标用户分层/], 0.88],
    ["research_plan", [/验证.*痛点|访谈样本|通过标准|调研计划|research plan|样本|验证计划/], 0.88],
    ["interview_guide", [/访谈提纲|访谈问题|不要诱导|interview guide|用户访谈/], 0.9],
    ["interview_synthesis", [/访谈完|记录很乱|提炼共性|分歧|反例|research synthesis|访谈总结/], 0.9],
    ["persona_jtbd_journey", [/JTBD|旅程|什么时候会放弃|为什么会用|用户旅程|persona|job to be done/], 0.9],
    ["opportunity_tree", [/机会树|拆机会|机会.*方案.*实验|目标结果.*确定|opportunity tree/], 0.9],
    ["assumption_mapping", [/危险的假设|假设.*排序|重要性.*不确定性|assumption|风险假设/], 0.9],
    ["value_sizing", [/值不值得做|估算收益|成本和不确定性|价值评估|收益.*成本|value sizing|ROI/], 0.88],
    ["prioritization", [/先做哪个|哪些先不做|优先级|排序|prioritization|RICE|ICE|MoSCoW|都有人催|above.*line|below.*line/], 0.9],
    ["solution_exploration", [/几种解法|列方案|比较取舍|方案比较|solution options|option a|option b|credible ways/], 0.88],
    ["mvp_scope", [/先做 MVP|砍范围|not-do|不要做大|scope cutting|MVP 范围|最小可行|第一阶段.*(主打|做|范围|切入|先做)|阶段.*切入点/], 0.92],
    ["one_page_proposal", [/一页方案|一页纸|拿给业务方|过一下方向|one[-\s]?page|one\s*pager|exec summary|资源申请|方向说明/], 0.88],
    ["data_feasibility_precheck", [/数据可不可行|客户数据|推荐逻辑|数据可行性|data feasibility/], 0.9],
    ["technical_feasibility_precheck", [/技术可行|自动化.*权限.*接口|研发视角|能不能做|technical feasibility|架构风险/], 0.9],
    ["compliance_precheck", [/合规|隐私|外部消息触达|法务|compliance|personal data|敏感数据/], 0.9],
    ["core_flow_diagram", [/核心流程|流程图|异常分支|用户.*系统|flow diagram|core[-_\s]?flow|泳道|状态流转|待审队列.*AI.*(质检|回流)/], 0.88],
    ["low_fi_prototype", [/原型图|低保真|画个原型|类似.*首页|信息流首页|prototype|wireframe|mockup|UI草图/], 0.94],
    ["metrics_design", [/北极星指标|输入指标|护栏指标|指标树|metrics design|north star|KPI/], 0.9],
    ["instrumentation_plan", [/埋点|事件属性|触发时机|instrumentation|tracking plan|数据采集/], 0.9],
    ["prd_outline", [/PRD.*大纲|prd.*outline|搭大纲|不要直接写长文|准备写 PRD/], 0.9],
    ["prd_v0_draft", [/PRD 初稿|写 PRD|prd draft|根据前面的材料.*PRD|假设.*标出来/], 0.9],
    ["pm_self_review", [/产品自审|先别叫研发|PRD 写完了|self-review|自己先审/], 0.9],
    ["internal_product_review", [/组内.*PRD|内部产品评审|拉必要角色评审|internal product review/], 0.9],
    ["design_review", [/设计视角|设计评审|路径.*状态.*文案|原型和流程|design review|UX review/], 0.9],
    ["data_review", [/数据负责人评审|指标.*推荐逻辑.*评审|数据评审|data review/], 0.9],
    ["technical_pre_review", [/技术预评审|研发看看.*PRD|系统边界|依赖和工期|technical pre-review/], 0.9],
    ["formal_requirements_review", [/正式需求评审|通过.*条件通过.*驳回|formal requirements review|评审结论/], 0.92],
    ["task_breakdown", [/拆 Epic|Story|Task|任务拆解|依赖|task breakdown|PRD 过了/], 0.9],
    ["acceptance_criteria", [/怎么验收|Given\/When\/Then|验收标准|测试场景|acceptance criteria/], 0.9],
    ["development_tracking", [/研发过程中|范围变了|记录变更|是否接受|development tracking|scope change/], 0.9],
    ["integration_qa", [/联调|测试快结束|bug|能不能上线|integration QA|集成测试/], 0.9],
    ["launch_readiness", [/准备上线|上线检查|灰度.*监控.*回滚|go\/no-go|go\s*no\s*go|launch readiness|客服.*运营.*就绪/], 0.92],
    ["training_enablement", [/一线.*培训|SOP.*FAQ.*话术|培训材料|training enablement|客服话术/], 0.9],
    ["grey_release_pilot", [/灰度试点|灰度范围|回滚条件|pilot|beta|小流量|试点指标/], 0.9],
    ["launch_monitoring", [/上线后每天看什么|监控清单|异常记录|launch monitoring|质量投诉|support tickets/], 0.9],
    ["post_launch_review", [/上线一周|复盘|结果.*问题.*经验|postmortem|post-launch|lessons/], 0.9],
    ["iteration_planning", [/下一版|迭代 backlog|基于复盘和数据|iteration planning|next quarter|roadmap/], 0.9],
    ["project_intake", [/新产品方向|建个项目|想做一个产品|开始一个项目|project intake|开项目/], 0.82],
    ["request_triage", [/不知道先处理哪个|下一步怎么走|判断.*阶段|标准sop|先做什么|triage|一堆会议纪要/], 0.78]
  ].freeze

  attr_reader :prompt_eval_path

  def initialize(prompt_eval_path:, embedding_mode: ENV["PCO_STAGE_ROUTER_EMBEDDING"].to_s, vector_db_path: nil)
    @prompt_eval_path = prompt_eval_path
    @embedding_mode = embedding_mode.to_s
    @vector_db_path = vector_db_path
    @last_retrieval_metadata = default_retrieval_metadata
    @cases = load_cases(prompt_eval_path)
    @cases_by_stage = @cases.each_with_object({}) do |entry, memo|
      memo[entry.fetch("stage_id")] ||= entry
    end
  end

  def route(user_input)
    text = user_input.to_s.strip
    @last_retrieval_metadata = default_retrieval_metadata
    product_like = product_signal?(text)
    if !product_like && DOMAIN_EXIT_PATTERNS.any? { |pattern| text.match?(pattern) }
      return non_product_route(text, "matched_non_product_pattern")
    end

    retrieval_candidates = retrieve_candidates(text)
    scored = ROUTES.map do |stage_id, patterns, base_confidence|
      hits = patterns.select { |pattern| text.match?(pattern) }
      [stage_id, hits, base_confidence]
    end.select { |_stage_id, hits, _confidence| hits.any? }

    if scored.empty?
      top_candidate = retrieval_candidates.first
      confidence_gap = candidate_confidence_gap(retrieval_candidates)
      if top_candidate && retrieval_confident?(top_candidate, confidence_gap)
        return build_route(
          stage_id: top_candidate.fetch("stage_id"),
          confidence: [0.72 + top_candidate.fetch("score"), 0.84].min,
          matched_signals: top_candidate.fetch("matched_terms"),
          route_status: product_like ? "retrieval_mapped" : "scope_retrieval_mapped",
          candidate_routes: retrieval_candidates
        )
      end

      return non_product_route(text, "no_product_signal_or_confident_retrieval") unless product_like

      return build_route(
        stage_id: "request_triage",
        confidence: 0.55,
        matched_signals: ["product signal found but no specific stage matched"],
        route_status: "needs_clarification",
        candidate_routes: retrieval_candidates
      )
    end

    stage_id, hits, base_confidence = scored.max_by { |_stage, hit_list, confidence| [hit_list.length, confidence] }
    confidence = [base_confidence + ((hits.length - 1) * 0.03), 0.97].min
    build_route(
      stage_id: stage_id,
      confidence: confidence,
      matched_signals: hits.map(&:source),
      route_status: "mapped",
      candidate_routes: retrieval_candidates
    )
  end

  private

  def load_cases(path)
    return [] unless File.exist?(path)

    YAML.load_file(path).fetch("cases")
  end

  def product_signal?(text)
    PRODUCT_SIGNALS.any? { |pattern| text.match?(pattern) }
  end

  def tokenize(text)
    raw = text.to_s.downcase
    latin_tokens = raw.scan(/[a-z0-9_]{2,}/)
    han_text = raw.scan(/\p{Han}+/).join
    han_chars = han_text.chars
    han_bigrams = han_chars.each_cons(2).map(&:join)
    han_trigrams = han_chars.each_cons(3).map(&:join)
    (latin_tokens + han_bigrams + han_trigrams).uniq.reject { |term| RETRIEVAL_STOP_TERMS.include?(term) }
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

  def retrieve_candidates(text)
    return retrieve_embedding_candidates(text) if embedding_enabled?

    retrieve_lexical_candidates(text)
  end

  def retrieve_lexical_candidates(text)
    query_terms = tokenize(text)
    return [] if query_terms.empty? || @cases.empty?

    candidates = @cases.map do |entry|
      case_terms = tokenize(case_search_text(entry))
      matched_terms = query_terms & case_terms
      next if matched_terms.empty?

      score = matched_terms.length.to_f / [query_terms.length, 1].max
      {
        "stage_id" => entry.fetch("stage_id"),
        "case_id" => entry.fetch("case_id"),
        "score" => score.round(3),
        "matched_terms" => matched_terms.first(8)
      }
    end.compact.sort_by { |candidate| [-candidate.fetch("score"), candidate.fetch("stage_id")] }.first(3)
    @last_retrieval_metadata = {
      "retrieval_mode" => candidates.empty? ? "rules_only" : "local_sop_rag",
      "embedding_status" => "not_requested",
      "real_embedding_performed" => false,
      "embedding_provider" => "",
      "embedding_model" => "",
      "source_refs" => candidates.flat_map { |candidate| candidate.fetch("source_refs", []) }.uniq
    }
    candidates
  end

  def retrieve_embedding_candidates(text)
    index = ProductCrewOS::SopEmbeddingIndex.new(prompt_eval_path: @prompt_eval_path, db_path: @vector_db_path)
    payload = index.retrieve(text, top_k: 3)
    candidates = payload.fetch("candidates")
    @last_retrieval_metadata = {
      "retrieval_mode" => payload.fetch("real_embedding_performed") ? "real_embedding_sop_rag" : "local_hash_dry_run_sop_rag",
      "embedding_status" => payload.fetch("real_embedding_performed") ? "real_embedding_performed" : "smoke_only_not_user_runtime",
      "real_embedding_performed" => payload.fetch("real_embedding_performed"),
      "embedding_provider" => payload.fetch("provider"),
      "embedding_model" => payload.fetch("model"),
      "source_refs" => candidates.flat_map { |candidate| candidate.fetch("source_refs", []) }.uniq
    }
    candidates
  rescue ProductCrewOS::EmbeddingProviders::ProviderError => e
    candidates = retrieve_lexical_candidates(text)
    @last_retrieval_metadata = @last_retrieval_metadata.merge(
      "embedding_status" => "runtime_blocked: #{e.message}",
      "real_embedding_performed" => false
    )
    candidates
  end

  def embedding_enabled?
    %w[1 true real required].include?(@embedding_mode.downcase)
  end

  def default_retrieval_metadata
    {
      "retrieval_mode" => "rules_only",
      "embedding_status" => "not_requested",
      "real_embedding_performed" => false,
      "embedding_provider" => "",
      "embedding_model" => "",
      "source_refs" => []
    }
  end

  def candidate_confidence_gap(candidates)
    return nil if candidates.length < 2

    (candidates[0].fetch("score") - candidates[1].fetch("score")).round(3)
  end

  def retrieval_confident?(top_candidate, confidence_gap)
    score = top_candidate.fetch("score")
    score >= 0.34 || (score >= 0.18 && (confidence_gap.nil? || confidence_gap >= 0.12))
  end

  def non_product_route(text, reason)
    {
      "product_crew_os_applies" => false,
      "domain_intent" => "non_product_task",
      "stage_id" => nil,
      "macro_stage" => nil,
      "confidence" => 0.9,
      "intent" => reason,
      "matched_signals" => [],
      "sop" => nil,
      "primary_skill" => nil,
      "fallback_skill" => nil,
      "required_roles" => [],
      "triggered_roles" => [],
      "required_artifacts" => [],
      "stage_gate" => nil,
      "candidate_routes" => [],
      "retrieval_mode" => "off",
      "embedding_status" => "not_applicable",
      "real_embedding_performed" => false,
      "embedding_provider" => "",
      "embedding_model" => "",
      "source_refs" => [],
      "confidence_gap" => nil,
      "scope_gate" => "hard_exit_or_no_confident_product_route",
      "routing_model" => "input_scope_gate_parallel_rule_embedding",
      "skill_router_enabled" => false,
      "route_status" => "domain_exit",
      "next_action" => "直接回答用户问题，或使用相关非产品能力。"
    }
  end

  def build_route(stage_id:, confidence:, matched_signals:, route_status:, candidate_routes: [])
    reference = @cases_by_stage.fetch(stage_id, {})
    expected = reference.fetch("expected", {})
    confidence_gap = candidate_confidence_gap(candidate_routes)
    retrieval_metadata = @last_retrieval_metadata || default_retrieval_metadata
    {
      "product_crew_os_applies" => true,
      "domain_intent" => "product_work",
      "stage_id" => stage_id,
      "macro_stage" => reference["macro_stage"],
      "confidence" => confidence.round(2),
      "intent" => stage_id,
      "matched_signals" => matched_signals,
      "sop" => stage_id,
      "primary_skill" => expected["primary_skill"],
      "fallback_skill" => expected["fallback_skill"],
      "required_roles" => expected["required_roles"] || [],
      "triggered_roles" => expected["triggered_roles"] || [],
      "required_artifacts" => expected["required_artifacts"] || [],
      "stage_gate" => expected["stage_gate"],
      "candidate_routes" => candidate_routes,
      "retrieval_mode" => candidate_routes.empty? ? "rules_only" : retrieval_metadata.fetch("retrieval_mode"),
      "embedding_status" => retrieval_metadata.fetch("embedding_status"),
      "real_embedding_performed" => retrieval_metadata.fetch("real_embedding_performed"),
      "embedding_provider" => retrieval_metadata.fetch("embedding_provider"),
      "embedding_model" => retrieval_metadata.fetch("embedding_model"),
      "source_refs" => retrieval_metadata.fetch("source_refs"),
      "confidence_gap" => confidence_gap,
      "scope_gate" => "hard_exit_checked",
      "routing_model" => "input_scope_gate_parallel_rule_embedding",
      "skill_router_enabled" => true,
      "route_status" => route_status,
      "next_action" => route_status == "needs_clarification" ? "先澄清用户要推进的产品阶段，再调用 SOP。" : "读取 SOP，调用对应 skill，并按边界召唤必要角色。"
    }
  end
end
