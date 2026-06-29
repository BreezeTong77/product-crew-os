# Semantic Stage Router / 语义阶段路由器

本文件记录 Product Crew OS 的未来迭代能力：让主控教练更稳定地把用户自然语言映射到正确产品阶段、SOP、skill、子 Agent 和 artifact。

它不是一个单纯的 RAG 数据库功能，而是一套“语义识别 + 工作流路由 + 记忆检索 + 反馈学习”的产品能力。

## 0. 领域意图门 / Domain Intent Gate

在判断 `stage_id` 之前，主控教练必须先判断这一轮是否应该进入 Product Crew OS。

Product Crew OS 只接管两类请求：

- `product_work`：产品想法、需求、调研、商业判断、方案、PRD、评审、原型、指标、交付、上线、复盘等产品经理工作。
- `product_crew_os_operation`：安装、配置、评估、修改 Product Crew OS 本身，包括 SOP、skill、角色、记忆、发布包和测试。

如果用户请求属于 `non_product_task`，例如普通翻译、闲聊、通用代码问题、生活问答、纯文件操作、与产品工作无关的信息查询，主控教练不要强行匹配 SOP，也不要进入 Skill Router、子 Agent Review Loop、Project Workspace 或 Stage Gate。

非产品请求的内部路由应类似：

```json
{
  "product_crew_os_applies": false,
  "domain_intent": "non_product_task",
  "stage_id": null,
  "sop": null,
  "skill_router_enabled": false,
  "response_mode": "normal_assistant",
  "next_action": "直接回答用户问题，或使用相关非产品能力。"
}
```

只有当 `product_crew_os_applies=true` 时，才继续执行 stage 判断、SOP 匹配、skill 选择和干系人评审。

## 1. 要解决的问题

用户不会按 Product Crew OS 的 stage 名称说话。

他们更常这样表达：

- “帮我画一个这个原型图。”
- “客户又提了个需求，帮我看看要不要做。”
- “我写完 PRD 了，你帮我过一下。”
- “这个产品方向感觉不错，下一步做什么？”
- “我们准备上线了，帮我检查一下。”

主控教练必须判断：

- 当前意图是什么。
- 应归一到哪个 `stage_id`。
- 应读取哪张 SOP 卡片。
- 应调用哪个 primary / fallback skill。
- 是否需要召唤子 Agent。
- 应生成或修改哪个 artifact。
- Stage Gate 是否能通过。

如果这一步判断错，后续 skill、子 Agent 和 artifact 都会跟着错。

## 2. 产品定义

Semantic Stage Router 是 Product Crew OS 的阶段判断引擎。

输入：

- 用户自然语言请求。
- 当前项目状态。
- 最近 artifact 和决策日志。
- 44 张 SOP 卡片。
- stage taxonomy、aliases 和 trigger examples。
- 用户偏好、团队风格、历史纠错记录。

输出：

```json
{
  "product_crew_os_applies": true,
  "domain_intent": "product_work",
  "stage_id": "low_fi_prototype",
  "confidence": 0.86,
  "intent": "create_ui_prototype_from_reference",
  "matched_signals": [
    "用户要求画原型图",
    "用户提供截图作为视觉来源"
  ],
  "sop": "23. Low-fi prototype",
  "primary_skill": "pencil-design",
  "fallback_skill": "figma:figma-use",
  "artifact": "low-fi-prototype-brief.md / HTML demo",
  "required_roles": ["Coach", "Design"],
  "next_action": "生成 HTML Demo，并由 Design 评审视觉还原和交互状态"
}
```

主控教练应把路由结果用于执行，而不是把它暴露成复杂后台日志。必要时只用用户听得懂的话说明：

> 你这一步其实是低保真原型，不是 PRD，也不是需求评审。我会先按原型 SOP 跑。

## 3. 分阶段实现路线

### M0：规则 + LLM 分类 + JSON SOP 表

目标：不用向量数据库，也能明显减少 stage 误判。

做法：

- 为 44 个 stage 维护名称、别名、典型用户说法、输入特征和排除条件。
- 每次用户输入时，先做 `domain_intent_gate`；只有确认为产品工作或 Product Crew OS 操作时，才输出内部 `stage_route_decision`。
- 当置信度低于阈值时，先澄清，不直接执行。
- 当用户纠正阶段判断时，记录为 routing feedback。
- 未命中 SOP 不等于自动进入 `request_triage`。只有 `product_crew_os_applies=true` 且 stage 仍不清楚时，才进入 `request_triage` 或提出澄清问题。

适合 v0.1.x 到 v0.2.x。

### M1：轻量检索

目标：让主控教练能从本地规则包和项目 workspace 中找相似依据。

可检索内容：

- `stage-taxonomy.md`
- `workflow-sop-library.md`
- `skill-stage-router.md`
- `stage-boundary-matrix.md`
- `usage-modes-and-trigger-examples.md`
- 项目中的 `decision-log.md`
- 历史 `stage-route-decision.jsonl`
- 用户批准的团队风格 overlay

实现可以先用本地 Markdown / JSON 检索，不强制上向量数据库。

适合 v0.2.x。

### M2：Embedding / 向量检索 / RAG

目标：当用户开始沉淀公司 SOP、历史项目、会议纪要、同事评论、真实 PRD 和团队风格后，能检索更像当前场景的上下文。

RAG 适合检索：

- 用户自己的公司流程。
- 历史相似项目。
- 过往 stage 误判和修正。
- 同事/子 Agent 的历史评审偏好。
- 项目内已有 artifact 和决策。

注意：

- RAG 不能替代 stage gate。
- 检索结果必须标注来源。
- 项目记忆、用户偏好、产品规则仍必须分容器保存。
- 真实公司材料不能进入公开产品规则包。

适合 v0.3.x 以后。

### M3：长期反馈学习

目标：让 Product Crew OS 越用越像用户自己的产品办公室。

可学习信号：

- 用户纠正：“这不是 PRD，是原型。”
- 用户偏好：“这种场景先拉设计，不要先写文档。”
- 子 Agent 反馈：“上次这个阶段漏了 Data。”
- 项目复盘：“这类需求总是先卡在技术可行性。”
- 团队材料：“我们公司研发特别谨慎，技术评审要更早进入。”

学习输出：

- 更新项目级 routing examples。
- 更新用户级偏好 overlay。
- 更新角色 context packet。
- 更新回归测试场景。
- 必要时建议修改默认规则，但不能自动写入公共规则包。

## 4. Routing 失败处理

当用户指出阶段判断错误时，主控教练必须：

1. 承认当前路由错误。
2. 给出正确 `stage_id` 和理由。
3. 说明本轮原本应该调用的 SOP / skill / 子 Agent / artifact。
4. 把错误归类为 routing feedback。
5. 询问是否写入项目记忆或用户偏好。
6. 如果这是产品规则缺口，建议进入 Product Rule Memory，但不能写入具体项目内容。

标准记录格式：

```json
{
  "event_type": "stage_routing_feedback",
  "user_utterance": "帮我画一个这个原型图",
  "wrong_stage": "none_or_generic_ui_task",
  "correct_stage": "low_fi_prototype",
  "expected_sop": "23. Low-fi prototype",
  "missed_roles": ["Design"],
  "missed_artifact": "HTML demo / low-fi prototype brief",
  "lesson": "UI prototype requests with screenshots should trigger low_fi_prototype before implementation."
}
```

## 5. 与 RAG 的关系

RAG 是手段，不是产品卖点。

产品卖点应该是：

> Product Crew OS 会越来越懂用户当前处在哪个产品阶段，并主动调用正确流程。

技术表达可以是：

```text
semantic intent classification
-> stage taxonomy retrieval
-> SOP / skill / stakeholder retrieval
-> project memory retrieval
-> route decision
-> artifact and review execution
-> routing feedback loop
```

对用户的表达应更简单：

> 你不用知道该选哪个流程。你说人话，我判断阶段，带你往下一步走。

## 6. 不做什么

- 不把所有用户材料混进公共产品规则。
- 不让向量数据库绕过记忆容器隔离。
- 不把相似案例检索结果当成事实来源。
- 不因为检索到了某个历史做法，就自动改变当前项目决策。
- 不把 stage router 做成用户必须手动选择的复杂菜单。

## 7. Stage Gate

Semantic Stage Router 进入可用状态需要满足：

- 44 个 stage 都有别名和触发样例。
- 每次实质工作前能输出内部 route decision。
- 低置信度时会澄清。
- 用户纠错会被记录为 routing feedback。
- route decision 能解释 SOP、skill、roles、artifact 和 next action。
- RAG 检索结果遵守 Product Rule Memory / User Preference Memory / Project Memory 隔离。
