# Workflow SOP Library

本文件定义 Product Crew OS 的细颗粒产品工作流 SOP。

它不是 skill 菜单，也不是外部能力包清单。它是主控教练在判断阶段之后使用的执行卡片：

```text
用户输入 -> 阶段识别 -> SOP 执行 -> artifact 输出 -> 必要评审 -> gate 判断 -> 下一步
```

主控教练可以按用户场景裁剪步骤，但不能跳过“输入、能力调用、输出 Artifact、子 Agent 调用、Stage Gate”这些关键判断。

## 1. 通用执行规则

每个阶段默认遵循以下顺序：

1. 复述当前目标：用一句话确认用户要推进什么。
2. 盘点输入：列出已知材料、缺失材料和可先假设的内容。
3. 选择 SOP：说明当前处于哪个 stage，为什么不是其他 stage。
4. 调用能力：选择内置 skill、用户自有 skill、artifact 模板或工具适配器。
5. 生成产物：优先写入 Artifact Workspace，而不是只发聊天气泡。
6. 召唤评审：只在阶段门、风险或用户要求时叫对应角色。
7. 过关判断：说明通过、条件通过、卡住或回退。
8. 给下一步：告诉用户下一步做什么、找谁对齐、需要补什么材料。

## 2. SOP 卡片字段

| 字段 | 含义 |
| --- | --- |
| 输入 | 用户或项目需要提供的信息 |
| 默认 SOP | 主控教练的标准推进动作 |
| 能力调用 | primary skill、fallback skill、用户自有 skill、artifact 模板或工具适配器 |
| 输出 Artifact | 应写入 Artifact Workspace 的产物 |
| 子 Agent 调用 | required roles、triggered roles 和默认不该出现的角色边界 |
| Review Loop | 子 Agent 如何给结论、卡点、建议，以及主控如何收束 |
| Stage Gate | 通过、条件通过、不通过或回退标准 |
| 下一阶段 | 通过后默认进入哪个 stage，失败时回退到哪里 |

## 3. 项目接入与机会发现

### 0. Project intake / 项目接入

| 字段 | 内容 |
| --- | --- |
| 输入 | 产品想法、背景、目标用户、业务方或客户来源、已有文件 |
| 默认 SOP | 建立项目卡；区分产品规则、用户偏好和项目记忆；确认用户称呼、主控教练和团队配置是否沿用默认；判断下一阶段 |
| 能力调用 | primary: `pm-workbench`；fallback: `product-manager-interrogation`；template: project card |
| 输出 Artifact | `project-card.md`，初始 `project-state.json` |
| 子 Agent 调用 | required: Coach；triggered: Biz if business target exists；Customer if external demand exists；out-of-bounds: Tech / Design / QA / Legal by default |
| Review Loop | Biz 只评业务目标和资源承诺；Customer 只还原外部诉求和验收压力；主控收束为项目卡缺口和下一阶段 |
| Stage Gate | 项目有目标用户、粗目标、负责人、当前阶段和下一步 artifact |
| 下一阶段 | 通过后进入 `request_triage`、`business_context` 或 `problem_definition`；不通过则追问最少必要信息 |

### 1. Request triage / 请求分流

| 字段 | 内容 |
| --- | --- |
| 输入 | 混杂需求、多个文件、用户一句模糊指令 |
| 默认 SOP | 拆分用户意图；识别是提问、生成、评审、修改还是推进流程；归一到 canonical stage；给出最小下一步 |
| 能力调用 | primary: `pm-workbench`；fallback: `product-manager-interrogation` |
| 输出 Artifact | `triage-note.md` 或项目状态栏 |
| 子 Agent 调用 | required: Coach；triggered: Research if evidence unclear；Biz if priority conflict；out-of-bounds: QA / Legal by default |
| Review Loop | Research 只指出证据缺口；Biz 只判断优先级和资源冲突；主控收束为当前阶段、最小下一步和暂不做事项 |
| Stage Gate | 用户知道现在在哪一步、先产出什么、暂时不做什么 |
| 下一阶段 | 通过后进入被归一化的目标 stage；不通过则停留 `request_triage` 继续澄清 |

### 2. Stakeholder map / 干系人地图

| 字段 | 内容 |
| --- | --- |
| 输入 | 业务方、研发、设计、客户、审批人、使用者、运营方 |
| 默认 SOP | 列出决策者、评审者、执行者、影响者；标记审批权、建议权和风险提示权；识别缺席角色 |
| 能力调用 | primary: `stakeholder-alignment-checker`；fallback: `pm-workbench` |
| 输出 Artifact | `stakeholder-map.md`，authority map |
| 子 Agent 调用 | required: Coach；triggered: Biz / Tech / Design / Data / CS / Customer as relevant owners or decision makers；out-of-bounds: QA unless delivery near |
| Review Loop | 被召唤角色只确认自己是否拥有审批权、建议权或风险提示权；主控收束为 authority map |
| Stage Gate | 谁能拍板、谁会卡住、谁必须被同步是清楚的 |
| 下一阶段 | 通过后进入 `business_context`、`problem_definition` 或当前用户目标 stage；不通过则补组织关系和拍板人 |

### 3. Business context / 商业背景

| 字段 | 内容 |
| --- | --- |
| 输入 | 商业目标、增长指标、降本目标、客户压力、预算、资源约束 |
| 默认 SOP | 写清业务问题；标注为什么现在要做；拆出收入、成本、效率、风险、战略价值；识别没有证据的判断 |
| 能力调用 | primary: `product-strategy`；fallback: `pm-workbench` / `strategy-doc` |
| 输出 Artifact | `business-context-brief.md` |
| 子 Agent 调用 | required: Coach, Biz；triggered: Data if metric baseline is needed；out-of-bounds: Design / QA / Legal by default |
| Review Loop | Biz 评业务目标、资源压力和优先级；Data 只评基线、口径和观察窗口；主控收束为业务问题和待验证判断 |
| Stage Gate | 业务目标、成功压力和不做的代价明确 |
| 下一阶段 | 通过后进入 `evidence_inventory`、`problem_definition` 或 `value_sizing`；不通过则补业务目标或 business owner |

### 4. Existing workflow mapping / 现状流程梳理

| 字段 | 内容 |
| --- | --- |
| 输入 | 当前业务流程、人工操作、系统流转、角色分工、痛点截图或描述 |
| 默认 SOP | 画出现状流程；标出触发点、角色、系统、交接、等待、返工和异常；区分用户痛点和组织痛点 |
| 能力调用 | primary: `user-story-mapping`；fallback: `pm-workbench`；tool: Mermaid / Diagram / Flowchart |
| 输出 Artifact | `current-workflow-map.md`，swimlane 或 Mermaid flow |
| 子 Agent 调用 | required: Coach；triggered: CS / Ops if field workflow；Design if user surface exists；out-of-bounds: Legal unless compliance risk |
| Review Loop | CS/Ops 评真实执行和培训成本；Design 评用户路径和操作成本；主控收束为卡点、责任人、损耗和异常路径 |
| Stage Gate | 当前流程里的卡点、责任人和损耗可见 |
| 下一阶段 | 通过后进入 `problem_definition` 或 `solution_exploration`；不通过则补流程节点、截图或一线访谈 |

### 5. Evidence inventory / 证据盘点

| 字段 | 内容 |
| --- | --- |
| 输入 | 会议纪要、访谈、数据、截图、客户原话、销售反馈、竞品材料 |
| 默认 SOP | 把信息分成事实、原话、推断、假设和缺口；给每条结论标置信心等级；指出下一步验证方式 |
| 能力调用 | primary: `pm-workbench`；fallback: `research-synthesis` |
| 输出 Artifact | `evidence-inventory.md` |
| 子 Agent 调用 | required: Coach；triggered: Data for logs/data；Research for interviews；CS for field notes；Customer for direct demand/quote；out-of-bounds: Tech unless system evidence needed |
| Review Loop | 各角色只校验自己证据来源的可信度和缺口；主控收束为 confidence rating、evidence gaps 和 next validation |
| Stage Gate | 重要判断都有证据或明确标记为待验证 |
| 下一阶段 | 通过后进入 `problem_definition`、`research_plan` 或 `value_sizing`；不通过则回退补证据，暂不进入方案或 PRD |

## 4. 问题定义与用户理解

### 6. Problem definition / 问题定义

| 字段 | 内容 |
| --- | --- |
| 输入 | 痛点描述、目标用户、现有解决方式、业务影响 |
| 默认 SOP | 分离问题和方案；写出谁在什么场景被什么阻碍影响了什么结果；判断真伪需求 |
| 能力调用 | primary: `problem-statement`；fallback: `define-problem-statement`；reference: `demand-authenticity.md` |
| 输出 Artifact | `problem-statement.md`，真伪需求判断 |
| 子 Agent 调用 | required: Coach；triggered: Research if user motivation unclear；CS if field pain exists；Customer if external demand needs source context；Biz if business impact must be sized；out-of-bounds: Tech / QA / Legal by default |
| Review Loop | Research 评用户动机证据；CS 评一线痛点频率；Customer 还原外部诉求；Biz 评业务影响；主控收束为问题陈述和真假需求判断 |
| Stage Gate | 问题不再只是“想做某功能”，而是可验证的用户或业务阻碍 |
| 下一阶段 | 通过后进入 `user_segmentation`、`research_plan` 或 `opportunity_tree`；不通过则回退 `evidence_inventory` 或 `business_context` |

### 7. User segmentation / 用户分层

| 字段 | 内容 |
| --- | --- |
| 输入 | 用户类型、角色、公司规模、行为数据、使用频率、付费或决策关系 |
| 默认 SOP | 区分使用者、决策者、影响者和被影响者；选出第一阶段主用户；解释为什么不是其他人 |
| 能力调用 | primary: `jtbd-analysis`；fallback: `define-jtbd-canvas`；template: user segmentation |
| 输出 Artifact | `user-segmentation.md` |
| 子 Agent 调用 | required: Coach, Research；triggered: Data if behavioral segment exists；CS if customer success segment exists；out-of-bounds: Tech / QA by default |
| Review Loop | Research 评分层是否能解释动机；Data 评行为分层可信度；CS 评客户经营分层现实性；主控收束为第一阶段主用户和非目标用户 |
| Stage Gate | MVP 服务谁、不服务谁、为什么先服务这群人明确 |
| 下一阶段 | 通过后进入 `persona_jtbd_journey`、`research_plan` 或 `mvp_scope`；不通过则回退 `problem_definition` |

### 8. Research plan / 调研计划

| 字段 | 内容 |
| --- | --- |
| 输入 | 要验证的问题、目标样本、时间限制、可接触用户、决策用途 |
| 默认 SOP | 写假设；定义样本；选择访谈、问卷、可用性测试或数据分析；设置通过和失败标准 |
| 能力调用 | primary: `product-discovery`；fallback: `pm-workbench`；template: validation plan |
| 输出 Artifact | `validation-plan.md` 或 `research-plan.md` |
| 子 Agent 调用 | required: Coach, Research；triggered: CS if recruiting from customers；Biz if leadership asks for proof；out-of-bounds: Tech / QA by default |
| Review Loop | Research 评方法和样本；CS 评招募可行性和话术边界；Biz 评验证结论是否足够决策；主控收束为通过/失败标准 |
| Stage Gate | 调研问题、样本、方法、判断标准和用来决策的地方明确 |
| 下一阶段 | 通过后进入 `interview_guide` 或 `evidence_inventory`；不通过则回退 `problem_definition` |

### 9. Interview guide / 访谈提纲

| 字段 | 内容 |
| --- | --- |
| 输入 | 调研目标、用户画像、核心假设、不能诱导的敏感点 |
| 默认 SOP | 设计开场、场景追问、过去行为、现有替代方案、痛感强度、触发频率和结束确认；去掉诱导问题 |
| 能力调用 | primary: `product-discovery`；fallback: `summarize-interview`；template: interview guide |
| 输出 Artifact | `interview-guide.md` |
| 子 Agent 调用 | required: Coach, Research；triggered: CS if wording must fit customer context；out-of-bounds: Tech / Data / QA / Legal by default |
| Review Loop | Research 评是否诱导和是否覆盖过去行为；CS 评客户语境是否自然；主控收束为可执行访谈提纲 |
| Stage Gate | 问题能得到真实行为和证据，而不是用户礼貌赞同 |
| 下一阶段 | 通过后进入访谈执行和 `interview_synthesis`；不通过则回退 `research_plan` |

### 10. Interview synthesis / 访谈综合

| 字段 | 内容 |
| --- | --- |
| 输入 | 访谈记录、录音转写、用户原话、样本背景 |
| 默认 SOP | 按主题聚类；保留关键原话；标出共性、分歧、反例、情绪和未证实假设；转成可决策结论 |
| 能力调用 | primary: `research-synthesis`；fallback: `user-research-synthesis` |
| 输出 Artifact | `research-synthesis.md` |
| 子 Agent 调用 | required: Coach, Research；triggered: CS if enterprise/customer context matters；Biz if impact sizing is needed；out-of-bounds: Tech / QA by default |
| Review Loop | Research 评洞察与证据绑定；CS 评企业语境和一线解释；Biz 评业务影响是否足够决策；主控收束为洞察、反例和未证实假设 |
| Stage Gate | 洞察和建议都能回到样本证据 |
| 下一阶段 | 通过后进入 `persona_jtbd_journey`、`problem_definition` 或 `opportunity_tree`；不通过则补访谈或回退 `evidence_inventory` |

### 11. Persona / JTBD / Journey / 用户动机与旅程

| 字段 | 内容 |
| --- | --- |
| 输入 | 用户分层、访谈洞察、使用场景、目标任务、情绪阻碍 |
| 默认 SOP | 选择 persona、JTBD 或 journey；写出触发场景、进步目标、替代方案、关键痛点和机会点 |
| 能力调用 | primary: `jtbd-analysis`；fallback: `jobs-to-be-done` / `define-jtbd-canvas` |
| 输出 Artifact | `jtbd-or-journey.md` |
| 子 Agent 调用 | required: Coach, Research；triggered: CS for real customer context；Design for experience path；out-of-bounds: Tech / QA by default |
| Review Loop | Research 评动机和证据；CS 评真实客户场景；Design 评旅程路径和体验断点；主控收束为触发场景、进步目标和放弃原因 |
| Stage Gate | 团队知道用户为什么会用、什么时候会用、为什么会放弃 |
| 下一阶段 | 通过后进入 `opportunity_tree` 或 `solution_exploration`；不通过则回退 `interview_synthesis` 或 `user_segmentation` |

### 12. Opportunity tree / 机会树

| 字段 | 内容 |
| --- | --- |
| 输入 | 目标结果、问题定义、用户洞察、业务约束 |
| 默认 SOP | 从目标结果拆机会；机会下挂方案；方案下挂实验；标出证据强弱和依赖 |
| 能力调用 | primary: `opportunity-solution-tree`；fallback: `define-opportunity-tree` |
| 输出 Artifact | `opportunity-tree.md` |
| 子 Agent 调用 | required: Coach；triggered: Research for user evidence；Biz for business tradeoff；CS for field feedback；out-of-bounds: Tech / QA / Legal by default |
| Review Loop | Research 评机会是否来自证据；Biz 评机会与业务目标的取舍；CS 评一线落地反馈；主控收束为目标、机会、方案、实验链路 |
| Stage Gate | 机会和方案不是散点，而是能回到目标结果 |
| 下一阶段 | 通过后进入 `assumption_mapping`、`solution_exploration` 或 `prioritization`；不通过则回退 `problem_definition` |

### 13. Assumption mapping / 假设地图

| 字段 | 内容 |
| --- | --- |
| 输入 | 产品方案、业务目标、用户行为假设、技术和数据假设 |
| 默认 SOP | 枚举假设；按重要性和不确定性排序；识别最危险假设；定义验证动作 |
| 能力调用 | primary: `assumption-mapper`；fallback: `problem-clarity` |
| 输出 Artifact | `assumption-map.md`，必要时补 `validation-plan.md` |
| 子 Agent 调用 | required: Coach；triggered: Research for user assumptions；Tech for feasibility assumptions；Data for metric/data assumptions；out-of-bounds: Legal unless regulated |
| Review Loop | 各角色只评自己领域的高风险假设；主控按重要性和不确定性排序，并转成验证动作 |
| Stage Gate | 高风险假设有验证计划，不能直接带进 PRD 当事实 |
| 下一阶段 | 通过后进入 `value_sizing`、`prioritization` 或 `mvp_scope`；不通过则回退 `research_plan`、`data_feasibility_precheck` 或 `technical_feasibility_precheck` |

## 5. 价值判断与范围定义

### 14. Value sizing / 价值测算

| 字段 | 内容 |
| --- | --- |
| 输入 | 目标指标、影响人群、频率、现有成本、潜在收益、资源投入 |
| 默认 SOP | 估算价值区间；拆用户价值、业务价值、战略价值和风险价值；标明置信度 |
| 能力调用 | primary: `feature-investment-advisor`；fallback: `value-vs-effort`；template: value sizing note |
| 输出 Artifact | `value-sizing-note.md`，必要时补 `roi-assumption-table.md` |
| 子 Agent 调用 | required: Coach, Biz；triggered: Data for baseline/metric口径；CS for adoption likelihood；Customer for purchase/acceptance signal；out-of-bounds: Design / QA by default |
| Review Loop | Biz 评业务价值和取舍；Data 评基线、口径和置信度；CS/Customer 只评采用或购买信号；主控收束为价值区间、证据强度和决策建议 |
| Stage Gate | 做或不做的理由能被业务方理解和挑战；价值、成本和不确定性都有标注 |
| 下一阶段 | 通过后进入 `prioritization` 或 `mvp_scope`；不通过则回退 `evidence_inventory`、`business_context` 或 `research_plan` |

### 15. Prioritization / 优先级排序

| 字段 | 内容 |
| --- | --- |
| 输入 | 候选需求、价值、证据、成本、依赖、时间窗口 |
| 默认 SOP | 选合适框架；给分并解释；列 above-line、below-line 和 later；记录争议 |
| 能力调用 | primary: `prioritization-advisor`；fallback: `define-prioritization-framework`；template: prioritization stack |
| 输出 Artifact | `prioritization-stack.md`，`decision-log.md` 中追加排序依据和争议 |
| 子 Agent 调用 | required: Coach, Biz；triggered: Tech for effort/dependency；Data for impact confidence；CS for adoption urgency；Customer for customer deadline or boss pressure；out-of-bounds: Legal unless risk |
| Review Loop | Biz 评优先级和资源承诺；Tech 评工作量和依赖；Data 评影响置信度；CS/Customer 评外部时限；主控收束为 above-line、below-line、later 和拒绝理由 |
| Stage Gate | 先做什么、暂缓什么、为什么这样排有清晰依据，且争议项有 owner 或决策人 |
| 下一阶段 | 通过后进入 `mvp_scope` 或 `one_page_proposal`；不通过则回退 `value_sizing` 或 `assumption_mapping` |

### 16. Solution exploration / 方案探索

| 字段 | 内容 |
| --- | --- |
| 输入 | 问题定义、机会点、约束、可用资源、不可做事项 |
| 默认 SOP | 生成至少两个方案；比较收益、成本、体验、风险、依赖和可验证性；推荐一个小步方案 |
| 能力调用 | primary: `pm-workbench`；fallback: `opportunity-solution-tree` / `value-vs-effort`；template: solution options brief |
| 输出 Artifact | `solution-options-brief.md`，至少包含 2 个方案、取舍表和推荐方案 |
| 子 Agent 调用 | required: Coach；triggered: Design for UX path；Tech for feasibility；Data for data/AI/metric-heavy solution；CS for adoption concern；out-of-bounds: QA unless acceptance needed |
| Review Loop | Design 评用户路径和操作成本；Tech 评实现风险和替代方案；Data 评数据/指标可行性；CS 评一线采用阻力；主控收束为推荐方案、被拒方案和取舍理由 |
| Stage Gate | 团队不是只看到一个方案，而是看到至少两个可比较方案和明确取舍 |
| 下一阶段 | 通过后进入 `mvp_scope`、`data_feasibility_precheck`、`technical_feasibility_precheck` 或 `core_flow_diagram`；不通过则回退 `opportunity_tree` 或 `assumption_mapping` |

### 17. MVP scope / MVP 范围

| 字段 | 内容 |
| --- | --- |
| 输入 | 核心假设、优先级、方案方向、时间和资源约束 |
| 默认 SOP | 定义 MVP 要验证的一个核心假设；列 must/should/later/not-do；砍掉无法验证主假设的功能 |
| 能力调用 | primary: `scope-cutting`；fallback: `shape-up`；template: `templates/artifacts/mvp-scope.md` |
| 输出 Artifact | `mvp-scope.md`，`not-do-list.md` 或在 decision log 追加砍范围理由 |
| 子 Agent 调用 | required: Coach, Biz；triggered: Tech for effort/dependency；Design for experience closure；Data if metric/data feature；Customer if external commitment constrains scope；out-of-bounds: Legal unless regulated |
| Review Loop | Biz 评 MVP 是否能支持业务判断；Tech 评能否在 appetite 内交付；Design 评体验是否闭环；Data 评是否能验证假设；主控收束为 must/should/later/not-do |
| Stage Gate | MVP 小到能交付，又足以证明一个核心假设；not-do 不能被口头绕回 |
| 下一阶段 | 通过后进入 `one_page_proposal`、`core_flow_diagram` 或 `prd_outline`；不通过则回退 `prioritization` 或 `solution_exploration` |

### 18. One-page proposal / 一页方案

| 字段 | 内容 |
| --- | --- |
| 输入 | 业务目标、用户问题、方案、范围、风险、资源需求 |
| 默认 SOP | 写一页业务可读方案；突出为什么做、做什么、不做什么、要谁支持、下个决策点 |
| 能力调用 | primary: `pm-workbench`；fallback: `strategy-doc`；template: one-page proposal |
| 输出 Artifact | `one-page-proposal.md`，必要时更新 `decision-log.md` |
| 子 Agent 调用 | required: Coach, Biz；triggered: Data for metrics；CS for field language；Tech if feasibility is challenged；Customer if proposal is for external acceptance；out-of-bounds: QA / Legal by default |
| Review Loop | Biz 评是否可批准方向和资源；Data 评指标承诺是否站得住；CS 评一线表达是否能被理解；Tech 只在可行性被质疑时发言；主控收束为批准条件和修改项 |
| Stage Gate | 业务负责人能基于这页材料批准方向、条件通过或提出明确修改 |
| 下一阶段 | 通过后进入 `data_feasibility_precheck`、`technical_feasibility_precheck`、`core_flow_diagram` 或 `prd_outline`；不通过则回退 `mvp_scope` 或 `value_sizing` |

## 6. 可行性、流程与原型

### 19. Data feasibility precheck / 数据可行性预检

| 字段 | 内容 |
| --- | --- |
| 输入 | 数据来源、字段、口径、刷新频率、数据 owner、权限和 SLA |
| 默认 SOP | 写数据契约草案；检查字段、来源、权限、质量、时效和归因；列缺口和替代方案 |
| 能力调用 | primary: `product-analytics`；fallback: `measure-dashboard-requirements`；template: `templates/artifacts/data-contract.md` |
| 输出 Artifact | `data-contract.md`，字段缺口和替代方案 |
| 子 Agent 调用 | required: Coach, Data；triggered: Tech if API/integration；Biz if data owner priority needed；Legal if personal/sensitive data；out-of-bounds: Design / QA by default |
| Review Loop | Data 评来源、字段、口径、刷新和可信度；Tech 评接口和权限；Biz 评 owner 协调；Legal 只评数据合规红线；主控收束为数据契约和阻塞项 |
| Stage Gate | 数据来源、字段、口径、owner、SLA 和风险明确；未知不能被带进指标或 PRD 当事实 |
| 下一阶段 | 通过后进入 `metrics_design`、`instrumentation_plan` 或 `prd_outline`；不通过则回退 `solution_exploration` 或 `evidence_inventory` |

### 20. Technical feasibility precheck / 技术可行性预检

| 字段 | 内容 |
| --- | --- |
| 输入 | 方案范围、系统边界、接口、权限、性能、AI 或自动化逻辑 |
| 默认 SOP | 拆系统边界；列依赖、未知、技术风险、工作量级别和替代实现；判断是否阻塞 PRD |
| 能力调用 | primary: `prd-critic`；fallback: `bmad-business-analyst`；template: `templates/artifacts/tech-feasibility-note.md` |
| 输出 Artifact | `tech-feasibility-note.md`，dependency list，open technical questions |
| 子 Agent 调用 | required: Coach, Tech；triggered: Data if data/API dependent；Design if surface complexity；QA if testability uncertain；Legal if security/compliance affects implementation；out-of-bounds: Biz unless scope negotiation |
| Review Loop | Tech 评系统边界、依赖、风险和替代实现；Data/Design/QA/Legal 只补各自领域阻塞；主控收束为可行、条件可行或阻塞 |
| Stage Gate | 没有未知阻塞项被带入 PRD；高风险项有 owner、验证方式或替代方案 |
| 下一阶段 | 通过后进入 `core_flow_diagram`、`low_fi_prototype` 或 `prd_outline`；不通过则回退 `mvp_scope` 或 `solution_exploration` |

### 21. Compliance precheck / 合规预检

| 字段 | 内容 |
| --- | --- |
| 输入 | 数据类型、隐私、合同、对外话术、财务或监管风险 |
| 默认 SOP | 标注敏感信息；检查权限、留痕、审计、合同承诺和对外表达；提出红线和替代方案 |
| 能力调用 | primary: `pm-workbench`；fallback: `stakeholder-alignment-checker`；template: compliance risk note |
| 输出 Artifact | `compliance-risk-note.md`，red-line list，approved wording constraints |
| 子 Agent 调用 | required: Coach, Legal；triggered: Data if personal/sensitive data；Biz if policy exception or contractual promise；Customer if external acceptance wording is involved；out-of-bounds: Design / QA by default |
| Review Loop | Legal 评隐私、合同、审计和对外表达红线；Data 评数据分类；Biz 评例外是否值得承担；Customer 只还原外部验收压力；主控收束为红线、可替代方案和待确认法务问题 |
| Stage Gate | 合规约束和红线清楚，后续文档不会越界；不能确认的红线必须进入 open questions |
| 下一阶段 | 通过后进入 `prd_outline`、`core_flow_diagram` 或 `launch_readiness`；不通过则回退 `solution_exploration` 或暂停外部承诺 |

### 22. Core flow diagram / 核心流程图

| 字段 | 内容 |
| --- | --- |
| 输入 | 用户目标、关键场景、角色、系统、状态、异常路径 |
| 默认 SOP | 先画主路径；再补异常、回退、失败、权限和通知；必要时输出 Mermaid |
| 能力调用 | primary: `user-story-mapping`；fallback: `figma:figma-generate-diagram` when authorized；tool/template: Mermaid / flowchart |
| 输出 Artifact | `core-flow.md`，Mermaid flow 或 swimlane；必要时导出 diagram brief |
| 子 Agent 调用 | required: Coach, Design；triggered: Tech for system states；Data for tracking events；CS for real-world handoff；Legal if regulated flow；out-of-bounds: QA unless acceptance needed |
| Review Loop | Design 评路径和信息架构；Tech 评系统状态和异常；Data 评事件追踪点；CS 评现实交接；主控收束为主路径、异常路径和状态清单 |
| Stage Gate | 团队能看懂用户和系统如何流转，以及哪里会失败；主路径和关键异常都可被引用进 PRD |
| 下一阶段 | 通过后进入 `low_fi_prototype`、`metrics_design` 或 `prd_outline`；不通过则回退 `solution_exploration` 或 `technical_feasibility_precheck` |

### 23. Low-fi prototype / 低保真原型

| 字段 | 内容 |
| --- | --- |
| 输入 | 核心流程、页面列表、目标用户、要验证的问题、品牌或视觉约束 |
| 默认 SOP | 先定义原型目标和页面状态；建议 image 概念图看方向；再做 HTML Demo 验证点击路径；用户授权后承接 Pencil/Figma |
| 能力调用 | primary: `pencil-design`；fallback: `figma:figma-use` when authorized；template: `templates/artifacts/low-fi-prototype-brief.md`；tool path: image concept -> HTML Demo -> Pencil/Figma |
| 输出 Artifact | `low-fi-prototype-brief.md`，image prompt，HTML demo brief，可选 Pencil/Figma 写入计划 |
| 子 Agent 调用 | required: Coach, Design；triggered: CS for adoption/usability；Customer for customer validation；Tech for component feasibility；Data if measurement points are embedded；out-of-bounds: QA / Legal by default |
| Review Loop | Design 评屏幕、状态和信息架构；CS/Customer 评是否能被真实用户理解；Tech 评组件和交互可行性；Data 评关键行为是否可记录；主控收束为原型范围和验证问题 |
| Stage Gate | 核心屏幕、用户决策点和交互状态可被测试；外部设计工具写入已获得用户授权或明确停留在 artifact/demo |
| 下一阶段 | 通过后进入 `metrics_design`、`prd_outline` 或 `design_review`；不通过则回退 `core_flow_diagram` |

### 24. Metrics design / 指标设计

| 字段 | 内容 |
| --- | --- |
| 输入 | 产品目标、用户行为、业务目标、成功和失败信号 |
| 默认 SOP | 定义北极星或主指标；拆输入指标、护栏指标和诊断指标；设观察窗口和复盘节奏 |
| 能力调用 | primary: `metrics-framework`；fallback: `north-star-metric`；template: metrics tree |
| 输出 Artifact | `metrics-tree.md`，metric definitions，review cadence |
| 子 Agent 调用 | required: Coach, Data；triggered: Biz for target；Tech for instrumentation effort；CS for behavior interpretation；out-of-bounds: Design / QA by default |
| Review Loop | Data 评指标口径、归因和观察窗口；Biz 评业务目标是否匹配；Tech 评实现成本；CS 评行为解释是否贴近一线；主控收束为主指标、输入指标、护栏指标和复盘节奏 |
| Stage Gate | 成功指标、输入指标、护栏指标和复盘窗口明确；指标不会鼓励错误行为 |
| 下一阶段 | 通过后进入 `instrumentation_plan` 或 `prd_outline`；不通过则回退 `value_sizing` 或 `data_feasibility_precheck` |

### 25. Instrumentation plan / 埋点计划

| 字段 | 内容 |
| --- | --- |
| 输入 | 核心流程、事件、属性、触发时机、数据用途 |
| 默认 SOP | 列事件表；定义属性、触发时机、去重口径、owner、验证方式；检查隐私 |
| 能力调用 | primary: `measure-instrumentation-spec` if available；fallback: `product-analytics`；template: tracking plan |
| 输出 Artifact | `tracking-plan.md`，event spec，data QA checklist |
| 子 Agent 调用 | required: Coach, Data；triggered: Tech for implementation；QA for validation if near delivery；Legal if privacy/personal data；Design if UI state affects trigger；out-of-bounds: Biz unless target changes |
| Review Loop | Data 评事件、属性、口径和用途；Tech 评实现点；QA 评如何验收；Legal 评隐私边界；主控收束为事件表、owner 和验收方式 |
| Stage Gate | 事件、属性、触发时机、owner 和验收方式可执行；隐私风险已标记或清除 |
| 下一阶段 | 通过后进入 `prd_outline`、`data_review` 或 `acceptance_criteria`；不通过则回退 `metrics_design` 或 `data_feasibility_precheck` |

## 7. PRD 与评审

### 26. PRD outline / PRD 大纲

| 字段 | 内容 |
| --- | --- |
| 输入 | 问题、目标、范围、方案、流程、指标、约束 |
| 默认 SOP | 按决策需要搭 PRD 结构；标注未确认内容；决定是否需要 Deep Artifact Pack |
| 能力调用 | primary: `prd-development`；fallback: `prd-writing`；template: `templates/artifacts/deep-artifact-pack.md` when formal review needs more depth |
| 输出 Artifact | `prd-outline.md`，必要时补 `deep-artifact-pack.md` 的目录骨架 |
| 子 Agent 调用 | required: Coach；triggered: Biz / Design / Tech / Data only if their domain is core to the PRD decision；out-of-bounds: QA / Legal by default |
| Review Loop | 被触发角色只检查 PRD 结构是否足够承载本领域评审，不提前替代正式评审；主控收束为大纲缺口、未确认项和后续评审计划 |
| Stage Gate | PRD 大纲包含问题、目标、范围、流程、指标、风险、未决问题和评审计划，而不是只有功能列表 |
| 下一阶段 | 通过后进入 `prd_v0_draft`；若问题、范围、流程或指标缺失，则回退 `mvp_scope`、`core_flow_diagram` 或 `metrics_design` |

### 27. PRD v0 draft / PRD 初稿

| 字段 | 内容 |
| --- | --- |
| 输入 | PRD 大纲、已确认范围、流程、指标、约束、待确认项 |
| 默认 SOP | 生成 PRD v0；把假设、风险和待确认项显性化；避免把未验证内容写成事实 |
| 能力调用 | primary: `deliver-prd`；fallback: `prd-taskmaster`；template: PRD v0 template |
| 输出 Artifact | `prd-v0.md`，`open-questions.md` 或 PRD 内的 assumption / risk section |
| 子 Agent 调用 | required: Coach；triggered: no sub-agent by default；out-of-bounds: Biz / Tech / Design / Data / QA / Legal unless user explicitly asks for review |
| Review Loop | 本阶段默认不召开评审会；主控用 PRD skill 和模板完成初稿，并把假设、风险、缺口和待确认项标出来 |
| Stage Gate | PRD 初稿完整、可读、假设可见，足以进入产品自审；不能把未验证内容写成事实 |
| 下一阶段 | 通过后进入 `pm_self_review`；如果结构不完整，回退 `prd_outline` |

### 28. PM self-review / 产品自审

| 字段 | 内容 |
| --- | --- |
| 输入 | PRD v0、流程图、范围、指标、风险 |
| 默认 SOP | 检查问题、目标、范围、流程、边界、指标、验收、依赖和术语一致性；生成修订清单 |
| 能力调用 | primary: `prd-critic`；fallback: `product-manager-skills`；template: PRD self-review checklist |
| 输出 Artifact | `pm-self-review.md`，PRD 修订项，必要时更新 `prd-v0.md` |
| 子 Agent 调用 | required: Coach；triggered: one domain role only when an obvious issue belongs to Biz / Design / Data / Tech / QA / Legal；out-of-bounds: full review panel by default |
| Review Loop | 只在必要时叫一个对应角色补充风险；主控按 must-fix、should-fix、later 分类修订项，并决定是否能进入多人评审 |
| Stage Gate | PRD 没有明显自相矛盾；关键缺口已修复或进入 review items；才允许进入多人评审 |
| 下一阶段 | 通过后进入 `internal_product_review`；不通过则回退 `prd_v0_draft` 或 `prd_outline` |

### 29. Internal product review / 内部产品评审

| 字段 | 内容 |
| --- | --- |
| 输入 | PRD、自审结果、争议点、需要团队决策的问题 |
| 默认 SOP | 按 must-fix、should-fix、later 分类评审意见；记录采纳、拒绝和待决策原因 |
| 能力调用 | primary: `utility-pm-critic`；fallback: `stakeholder-alignment-checker`；template: review notes + decision log |
| 输出 Artifact | `prd-review-notes.md`，`decision-log.md`，PRD revision plan |
| 子 Agent 调用 | required: Coach；triggered: Biz for priority/value；Design for UX；Data for metrics；Tech for feasibility；Legal if compliance risk appears；out-of-bounds: Customer unless external acceptance is involved |
| Review Loop | 每个被召唤角色先给结论，再绑定 PRD 具体章节说卡点和建议；主控记录采纳、拒绝和待决策原因，并收束为修订计划 |
| Stage Gate | 阻塞项被分类，owner 和处理方式明确，下一版 PRD 修改范围清楚 |
| 下一阶段 | 通过后按阻塞类型进入 `design_review`、`data_review`、`technical_pre_review` 或 `formal_requirements_review`；不通过则回退 `pm_self_review` |

### 30. Design review / 设计评审

| 字段 | 内容 |
| --- | --- |
| 输入 | 流程图、原型、页面状态、文案、交互约束 |
| 默认 SOP | 检查路径、信息架构、状态、错误提示、空状态、文案和操作成本；提出可改项 |
| 能力调用 | primary: `develop-design-rationale` if available；fallback: `user-story-mapping`；template: design review checklist |
| 输出 Artifact | `design-review-report.md`，UX issue list，page/state checklist |
| 子 Agent 调用 | required: Coach, Design；triggered: CS for usability/adoption；Tech for frontend/component constraints；Data if key behavior must be measured；out-of-bounds: Biz / Legal by default |
| Review Loop | Design 评路径、信息架构、状态和文案；CS 评真实用户是否能理解；Tech 评实现约束；主控收束为体验阻塞、可改项和可延后项 |
| Stage Gate | 用户路径、关键状态和核心文案清楚；体验阻塞项有 owner 或明确延后理由 |
| 下一阶段 | 通过后进入 `data_review`、`technical_pre_review` 或 `formal_requirements_review`；如果屏幕和路径不清楚，回退 `low_fi_prototype` 或 `core_flow_diagram` |

### 31. Data review / 数据评审

| 字段 | 内容 |
| --- | --- |
| 输入 | 指标树、数据契约、埋点计划、口径争议 |
| 默认 SOP | 检查数据来源、口径、归因、刷新、权限、监控和验收；记录数据阻塞项 |
| 能力调用 | primary: `product-analytics`；fallback: `metric-dashboard`；template: data review checklist |
| 输出 Artifact | `data-review-report.md`，metric / tracking blockers，data contract updates |
| 子 Agent 调用 | required: Coach, Data；triggered: Tech for API/instrumentation；Biz for target definition；Legal for sensitive/personal data；out-of-bounds: Design unless dashboard or UI state affects data |
| Review Loop | Data 评来源、口径、归因、刷新、权限和验收；Tech 评实现点；Biz 评目标口径；Legal 只评数据红线；主控收束为数据契约、阻塞项和 owner |
| Stage Gate | 数据契约被接受，或阻塞项有 owner、截止时间和替代方案；口径争议不能被带进上线 |
| 下一阶段 | 通过后进入 `technical_pre_review` 或 `formal_requirements_review`；不通过则回退 `data_feasibility_precheck`、`metrics_design` 或 `instrumentation_plan` |

### 32. Technical pre-review / 技术预评审

| 字段 | 内容 |
| --- | --- |
| 输入 | PRD、系统边界、接口、依赖、非功能要求 |
| 默认 SOP | 检查范围、架构、依赖、权限、性能、灰度、可测试性和工作量；提出替代方案 |
| 能力调用 | primary: `prd-critic`；fallback: `code-to-prd`；template: technical pre-review checklist |
| 输出 Artifact | `technical-pre-review.md`，risk / dependency list，open technical questions |
| 子 Agent 调用 | required: Coach, Tech；triggered: Data for data/API dependency；Design for UI complexity；QA for testability；Legal for security/compliance implementation constraints；out-of-bounds: Biz unless scope negotiation is needed |
| Review Loop | Tech 评系统边界、架构、依赖、权限、性能、灰度和工作量；其他角色只补领域阻塞；主控收束为可行、条件可行或阻塞 |
| Stage Gate | 系统边界、依赖、风险和替代方案清楚；没有未知技术阻塞被带进正式评审 |
| 下一阶段 | 通过后进入 `formal_requirements_review` 或 `task_breakdown`；不通过则回退 `mvp_scope`、`technical_feasibility_precheck` 或 `solution_exploration` |

### 33. Formal requirements review / 正式需求评审

| 字段 | 内容 |
| --- | --- |
| 输入 | 修订后 PRD、评审议题、决策人、待确认项 |
| 默认 SOP | 逐项确认范围、依赖、风险、指标、排期前提和责任人；记录批准、条件批准或驳回 |
| 能力调用 | primary: `stakeholder-alignment-checker`；fallback: `pm-workbench`；template: formal requirements review checklist |
| 输出 Artifact | `approved-prd.md`，`decision-log.md`，stage-gate result |
| 子 Agent 调用 | required: Coach；triggered: Biz / Tech / Design / Data as domain owners；Legal if compliance trigger exists；CS if support/operation readiness affects acceptance；Customer if external approval or contractual acceptance is required |
| Review Loop | 每个角色只对自己的领域给 approve、conditional approve 或 block；主控记录条件、责任人、截止时间和未决项，形成正式决策记录 |
| Stage Gate | 结论是批准、条件批准或驳回；条件、责任人、截止时间和未决项被记录；高影响事项需要人类 owner 认可 |
| 下一阶段 | 通过后进入 `task_breakdown`、`acceptance_criteria` 或交付排期；条件通过则先处理 owner 项；不通过则回退对应评审阶段 |

## 8. 交付拆解与开发跟踪

### 34. Task breakdown / 任务拆解

| 字段 | 内容 |
| --- | --- |
| 输入 | Approved PRD、范围、依赖、技术方案、设计稿或原型 |
| 默认 SOP | 拆 Epic、Story、Task；标 owner、依赖、估算和交付顺序；识别不可并行项 |
| 能力调用 | primary: `prd-taskmaster`；fallback: `deliver-user-stories`；template: `templates/artifacts/technical-task-breakdown.md` |
| 输出 Artifact | `technical-task-breakdown.md`，Epic / Story / Task 列表，dependency map |
| 子 Agent 调用 | required: Coach, Tech；triggered: Design for UI tasks；Data for data tasks；QA for test tasks；out-of-bounds: CS / Legal by default |
| Review Loop | Tech 评任务拆分、依赖、估算和不可并行项；Design/Data/QA 只补对应任务的交付要求；主控收束为任务列表、owner、依赖和验收入口 |
| Stage Gate | 每个任务有 owner、依赖、估算、交付顺序和验收入口；不可并行项被标出来 |
| 下一阶段 | 通过后进入 `acceptance_criteria` 或交付排期；不通过则回退 `formal_requirements_review` 或 `technical_pre_review` |

### 35. Acceptance criteria / 验收标准

| 字段 | 内容 |
| --- | --- |
| 输入 | User story、业务规则、页面状态、异常路径、数据规则 |
| 默认 SOP | 用 Given/When/Then 写通过条件；覆盖正常、异常、权限、边界和回归风险 |
| 能力调用 | primary: `deliver-acceptance-criteria`；fallback: `test-scenarios`；template: `templates/artifacts/test-scenario-library.md` |
| 输出 Artifact | `acceptance-criteria.md`，必要时补 `test-scenario-library.md` |
| 子 Agent 调用 | required: Coach, QA；triggered: Tech for implementation constraints；Design for UI states；Data for data validation；Biz for business rules only；out-of-bounds: CS / Legal by default |
| Review Loop | QA 评 pass/fail 是否可测试、边界是否覆盖；Tech/Design/Data/Biz 只补对应验收约束；主控收束为 Given/When/Then、边界场景和测试入口 |
| Stage Gate | 每个 story 都有可测试的 pass/fail；正常、异常、权限、边界和回归风险至少有最小覆盖 |
| 下一阶段 | 通过后进入 `development_tracking`、`integration_qa` 或交付排期；不通过则回退 `task_breakdown` 或相关 PRD 章节 |

### 36. Development tracking / 开发变更跟踪

| 字段 | 内容 |
| --- | --- |
| 输入 | 研发变更、技术发现、范围调整、延期风险、实现替代方案 |
| 默认 SOP | 记录变更来源；判断影响范围、价值、指标、设计、数据和验收；决定接受、延后或拒绝 |
| 能力调用 | primary: `pm-workbench`；fallback: `stakeholder-alignment-checker`；template: change log + decision note |
| 输出 Artifact | `change-log.md`，decision note，必要时更新 `decision-log.md` 和 affected artifact list |
| 子 Agent 调用 | required: Coach；triggered: Tech always for implementation changes；Biz if scope/value changes；Design if UX changes；Data if metric/data changes；QA if acceptance or release risk changes；out-of-bounds: CS / Legal unless support, contract, privacy, or compliance impact appears |
| Review Loop | Tech 先说明变更原因和替代方案；被影响角色只判断本领域是否接受；主控记录接受、延后或拒绝，并写明影响范围、owner 和后续 artifact 修改 |
| Stage Gate | 每个变更都有来源、影响范围、决策结果、owner 和关联 artifact；变更不能口头消失 |
| 下一阶段 | 接受后更新任务、验收或 PRD；延后进入 backlog / later；拒绝则保留原因；重大变更回退 `formal_requirements_review` 或 `task_breakdown` |

## 9. 测试、上线与运营

### 37. Integration / QA / 联调测试

| 字段 | 内容 |
| --- | --- |
| 输入 | 测试环境、任务完成情况、bug、验收标准、埋点验证 |
| 默认 SOP | 按严重程度分类 bug；检查核心路径、异常路径、数据、权限、兼容和回归；评估 release risk |
| 能力调用 | primary: `test-scenarios`；fallback: `deliver-acceptance-criteria`；template: `templates/artifacts/test-scenario-library.md` |
| 输出 Artifact | `qa-report.md`，bug list，release risk note，必要时更新 `test-scenario-library.md` |
| 子 Agent 调用 | required: Coach, QA；triggered: Tech for fixes/environment/incidents；Data for event validation；Design for UX defects；Biz only for go/no-go tradeoff；out-of-bounds: CS / Legal unless support, privacy, compliance, or external promise is impacted |
| Review Loop | QA 先给 release risk 结论；Tech/Data/Design 只处理对应缺陷或验证缺口；Biz 只在是否带缺陷上线时进入；主控收束为 bug 分级、阻塞项、签字放行条件和回归入口 |
| Stage Gate | P0/P1 已解决或有明确签字放行；核心路径、异常路径、权限、数据和回归风险有检查记录；发布风险明确 |
| 下一阶段 | 通过后进入 `launch_readiness`；不通过则回退 `development_tracking`、`acceptance_criteria` 或对应修复任务 |

### 38. Launch readiness / 上线准备

| 字段 | 内容 |
| --- | --- |
| 输入 | 发布范围、上线窗口、回滚方案、监控、客服话术、培训材料 |
| 默认 SOP | 检查上线清单；确认 owner、监控、灰度、回滚、通知、支持和风险预案 |
| 能力调用 | primary: `deliver-launch-checklist`；fallback: `test-scenarios`；template: `templates/artifacts/launch-checklist.md` |
| 输出 Artifact | `launch-checklist.md`，rollback plan，monitoring plan，support / comms plan |
| 子 Agent 调用 | required: Coach, QA；triggered: Tech for fallback/rollback；Data for monitoring；Ops for rollout/SOP；CS for support and customer communication；Legal if compliance, privacy, contract, or external messaging trigger exists；out-of-bounds: Design unless launch UX issue exists |
| Review Loop | QA 评上线风险；Tech 评回滚和应急；Data 评监控口径；Ops/CS 评通知、培训和支持；Legal 只评红线；主控收束为 go/no-go owner、上线窗口、回滚方案和风险预案 |
| Stage Gate | 上线、监控、支持、回滚、通知和风险预案都有 owner；go/no-go 条件可被执行 |
| 下一阶段 | 通过后进入 `training_enablement`、`grey_release_pilot` 或正式上线；不通过则回退 `integration_qa` 或 `development_tracking` |

### 39. Training / enablement / 培训赋能

| 字段 | 内容 |
| --- | --- |
| 输入 | 使用对象、流程变化、培训材料、常见问题、一线反馈渠道 |
| 默认 SOP | 写 SOP、FAQ 和培训话术；定义一线遇到问题怎么反馈；设置学习和采用检查点 |
| 能力调用 | primary: `pm-workbench`；fallback: `stakeholder-alignment-checker`；template: enablement SOP / FAQ / training brief |
| 输出 Artifact | `enablement-sop.md`，`faq.md`，`training-brief.md`，feedback channel plan |
| 子 Agent 调用 | required: Coach, Ops；triggered: CS for support scenarios；Biz for adoption owner or rollout pressure；Design for help copy and empty/error wording；Tech if tool operation requires technical explanation；Data if adoption metrics need dashboard training；out-of-bounds: Customer unless customer-facing enablement is required |
| Review Loop | Ops 评使用流程和培训节奏；CS 评一线问题和客户话术；Biz 评采用责任；Design/Tech/Data 只补对应材料；主控收束为 SOP、FAQ、培训口径和反馈回流机制 |
| Stage Gate | 使用者知道怎么用、遇到问题找谁、反馈怎么回流；培训材料和一线反馈 owner 明确 |
| 下一阶段 | 通过后进入 `grey_release_pilot` 或 `launch_readiness`；不通过则回退补上线准备、客服话术或产品文案 |

### 40. Grey release / pilot / 灰度试点

| 字段 | 内容 |
| --- | --- |
| 输入 | 试点对象、时间、指标、风险、回滚、反馈渠道 |
| 默认 SOP | 定义试点范围、周期、成功指标、失败条件、回滚方案和复盘时间 |
| 能力调用 | primary: `experiment-design`；fallback: `trustworthy-experiments`；template: pilot plan |
| 输出 Artifact | `pilot-plan.md`，success / failure criteria，rollback plan，feedback log |
| 子 Agent 调用 | required: Coach, Biz；triggered: Data for metrics and observation window；CS for customer feedback；Ops for rollout operation；QA for release risk；Tech for rollback/fallback；Legal if regulated or external promise exists |
| Review Loop | Biz 评试点目标和范围；Data 评指标、样本和观察窗口；CS/Ops 评反馈和运营路径；QA/Tech 评风险和回滚；主控收束为试点计划、放量条件、停止条件和复盘时间 |
| Stage Gate | 试点范围、周期、成功指标、失败条件、回滚方案、反馈渠道和复盘时间明确；不得从灰度直接口头变全量 |
| 下一阶段 | 通过后进入 `launch_monitoring` 或全量上线准备；不通过则回退 `launch_readiness`、`training_enablement` 或 `integration_qa` |

## 10. 上线监控、复盘与迭代

### 41. Launch monitoring / 上线监控

| 字段 | 内容 |
| --- | --- |
| 输入 | 指标数据、告警、客服反馈、事故、使用行为 |
| 默认 SOP | 设日/周监控节奏；区分指标波动、bug、使用问题和预期外行为；记录处理动作 |
| 能力调用 | primary: `product-analytics`；fallback: `metric-dashboard`；template: launch monitoring notes / issue log |
| 输出 Artifact | `launch-monitoring-notes.md`，metric watchlist，incident / adoption issue log |
| 子 Agent 调用 | required: Coach, Data；triggered: Tech for incidents or performance issues；CS / Ops for adoption signals；QA for escaped defects；Biz if go/no-go or success interpretation is needed；out-of-bounds: Design unless UX issue appears |
| Review Loop | Data 先判断指标是否异常、是否达到观察窗口；Tech/CS/Ops/QA 只补对应事件和处理动作；Biz 只在业务结论或放量判断时进入；主控收束为监控结论、owner、处理动作和复盘时间 |
| Stage Gate | 指标、事故、反馈和采用信号按节奏被检查；异常有 owner 和处理动作；上线表现不靠感觉判断 |
| 下一阶段 | 观察窗口结束后进入 `post_launch_review`；若出现阻塞事故或重大偏差，回退 `development_tracking`、`integration_qa` 或 `launch_readiness` |

### 42. Post-launch review / 上线复盘

| 字段 | 内容 |
| --- | --- |
| 输入 | 目标达成、数据、用户反馈、上线问题、交付过程、决策记录 |
| 默认 SOP | 回看目标；复盘结果、偏差、原因、经验、失败和下一步；把教训写入项目记忆 |
| 能力调用 | primary: `pm-workbench`；fallback: `roadmap-planning`；template: `templates/artifacts/postmortem.md` |
| 输出 Artifact | `postmortem.md`，learnings，decision / memory delta，next-action list |
| 子 Agent 调用 | required: Coach；triggered: Biz for business result；Data for metric result；CS for adoption and customer feedback；Tech for delivery learning；Design / QA only if UX or quality issue is relevant |
| Review Loop | 各角色只围绕目标、事实、偏差、原因和下一步发言；主控把经验转成项目记忆、决策记录、后续 backlog 或停止/转向建议 |
| Stage Gate | 复盘有事实、结论、原因、责任人、下一步和记忆 delta；不能只总结情绪或泛泛表扬/批评 |
| 下一阶段 | 通过后进入 `iteration_planning`；如果结果推翻原问题，回退 `problem_definition`；如果观察窗口不足，回退 `launch_monitoring` |

### 43. Iteration planning / 迭代规划

| 字段 | 内容 |
| --- | --- |
| 输入 | 复盘结论、指标、用户反馈、遗留 backlog、资源窗口 |
| 默认 SOP | 重新判断问题；整理下一版 backlog；按证据和价值排序；决定继续、转向、停止或扩展 |
| 能力调用 | primary: `roadmap-planning`；fallback: `prioritization-advisor`；template: iteration backlog / roadmap update |
| 输出 Artifact | `iteration-backlog.md`，roadmap update，next validation plan |
| 子 Agent 调用 | required: Coach, Biz；triggered: Data for metric evidence；CS for field feedback；Research for user learning gaps；Tech for feasibility/debt；Design for UX iteration；QA only if delivery or regression risk is near |
| Review Loop | Biz 先确认下一轮目标和资源窗口；Data/CS/Research 提供证据；Tech/Design/QA 评实现和体验风险；主控收束为继续、转向、停止或扩展，以及下一轮范围和验证计划 |
| Stage Gate | 下一轮范围、验证计划、对齐对象、owner 和不做事项明确；迭代不是把 backlog 全部搬进下一版 |
| 下一阶段 | 通过后进入下一轮 `project_intake`、`problem_definition`、`prioritization`、`mvp_scope` 或 `task_breakdown`；不通过则回退 `post_launch_review` 或补证据 |

## 11. 使用边界

- SOP 是默认路径，不是硬性流程图。用户已有公司流程时，应将用户流程作为 overlay。
- SOP 可以被用户自有 skill、模板、公司规范替换，但替换后仍要保留输入、输出、干系人和过关标准。
- 不要把所有 SOP 一次性展示给新用户。新用户只需要看到当前阶段和下一步。
- 高阶用户可以要求打开完整 SOP 库、能力面板或 stage gate。
- 外部工具、MCP、Pencil、Figma、Jira、Notion、飞书等只是执行通道，不能替代 SOP 判断。
