# 变更日志

Product Crew OS 的重要变更都会记录在这里。

## Unreleased

- 增加 Product Crew OS 领域意图门：先判断用户请求是否属于产品工作或 Product Crew OS 自身配置/维护，再进入 stage、SOP、Skill Router、子 Agent Review Loop 和 Stage Gate。
- 明确非产品请求不会被强行归入 `request_triage`、不会调用产品 skill、不会写入项目记忆，也不会召唤子 Agent。
- 新增 `non_product_task_exits_workflow` 回归场景，并让本地 regression runner 检查非产品任务不会误入产品工作流。
- 新增 Project Asset Pack 能力：定义项目资产包规则、Markdown/Obsidian-compatible 导出策略、项目首页、artifact 索引、时间线、决策日志、评审项、风险日志、下一步和导出清单模板。
- 新增 Project Memory Index Architecture：定义 SQLite/FTS/向量索引路线、数据库 CRUD、Obsidian 受控同步和长期记忆防覆盖机制。
- 新增最小本地 Runtime：基于 SQLite + Project Workspace 文件实现项目初始化、artifact 版本、决策、评审项、角色记忆、Context Packet、调用 ledger 和 Obsidian-compatible 导出，并新增 `run-runtime-smoke.rb` 验证真实写入链路。
- 新增 Runtime Adapter：`record-turn` 可将一次主控教练回合的 Stage、SOP、Skill、Artifact、Context Packet、调用 ledger、Review Item 和 Stage Gate 写入 SQLite。
- 新增 `run-sop-e2e-smoke.rb`：遍历 44 个 SOP prompt case，读取内置 skill，写入 `sop_runs`、`skill_runs`、artifact、context packet、invocation ledger 和 Obsidian 导出，验证 44 个 SOP 的最小端到端链路。
- 增强 Runtime 评估事件：`record-turn` 现在会写入 `stage_detected`、`skill_selected`、`memory_snapshot_built`、`agent_summoned` 和 `stage_gate_decision`，用于后续统计 Stage 命中率、Skill 命中率、团队记忆注入和评审发生情况。
- 新增 `runtime/create_demo_vault.rb`，可为其他用户生成持久 SQLite、Project Workspace 和 Obsidian-compatible Vault，不再只依赖临时测试目录。
- 新增 `references/runtime-adapter-contract.md`，定义宿主环境如何把主控回合、子 Agent 调用、Artifact、评审项、记忆和评估事件写入 Runtime。
- 新增 `references/coze-runtime-blueprint.md` 和 `integrations/coze/workflow-blueprint.yaml`，描述 Coze 式主 Bot、子 Bot、workflow node、数据库表和导出插件的可实现形态。
- 更新 `agents/openai.yaml`：项目初始化后，产品工作回合应自动写入 Project Runtime；用户偏好、产品规则和真实团队材料仍需显式授权或维护动作。
- 新增 `templates/adapters/host-note-adapter-prompt.md`，提供不同宿主环境和 Markdown 笔记工具的可复制适配提示词。
- README 和 Runtime Adapter Contract 明确 Obsidian 只是默认示例，用户可自行适配 Logseq、Foam、Dendron、VS Code、Typora、Notion、飞书或通用 Markdown 文件夹。

## v0.1.1 - 2026-06-28

### 发布定位

`v0.1.1` 是 Product Crew OS 的 GitHub 发布包：补齐 GitHub 首屏表达、44 个 SOP 卡片、内置 PM skill pack、语义阶段路由和发布前质检闭环。

### 优化

- 重写 README 首屏，让 GitHub 新访客先看到产品价值、适用人群和开始方式。
- 将产品描述收束为“AI 产品办公室”和 `Workflow-first AI Product Harness`，突出主控产品教练、可配置虚拟团队和 Artifact Workspace。
- 增加 badges、Start Here、可复制 prompt、Mermaid 工作流图和能力地图。
- 新增 `examples/first-run-demo.md` 和 `examples/prd-review-demo.md`。
- 明确本地质检命令和预期输出，方便用户 clone 后验证可用性。

### 新增

- 内置第三方 PM skill pack，位于 `product-crew-os-skill/third_party/skills/`，降低新用户部署成本。
- 新增 `product-crew-os-skill/references/bundled-skill-index.md`，让 Skill Router 可以优先解析随包内置能力。
- 新增 `product-crew-os-skill/THIRD_PARTY_NOTICES.md`，集中记录第三方 skill 的作者、来源和许可证声明。
- 新增 `product-crew-os-skill/references/semantic-stage-router.md`，记录语义阶段路由、RAG / 检索增强和 routing feedback 的未来迭代方案。

### 调整

- 将 Skill Router 说明从“推荐外部 skill”调整为“内置第三方 skill 优先，用户自有 skill 可覆盖”。
- README 和 LICENSE 增加第三方许可证边界，避免根目录 MIT License 覆盖第三方内容。
- 本地质检脚本增加对内置 skill pack、Notices 和 bundled index 的检查。
- README 明确用户复制完整 `product-crew-os-skill/` 后即可使用全流程内置能力，外部系统写入能力再按用户授权启用。
- 本地质检脚本会检查 bundled index 中声明的每个内置 skill 目录和 `SKILL.md` 是否真实存在。
- 完善 44 张 SOP 卡片全量 8 字段结构：输入、默认 SOP、能力调用、输出 Artifact、子 Agent 调用、Review Loop、Stage Gate、下一阶段。
- 完善 SOP 卡片 14-25，将价值测算、优先级、方案探索、MVP、可行性、流程、原型、指标和埋点阶段升级为 8 字段结构，并补齐对应 skill、子 Agent、Review Loop、Stage Gate 和下一阶段。
- 补齐 `solution_exploration` 和 `compliance_precheck` 的 stage-router 映射。
- 完善 SOP 卡片 26-33，将 PRD 大纲、PRD 初稿、产品自审、内部评审、设计评审、数据评审、技术预评审和正式需求评审升级为 8 字段结构，并补齐对应 skill、子 Agent、Review Loop、Stage Gate 和下一阶段。
- 扩展 Skill Dependency Registry 覆盖范围到 0-33，并标注 `develop-design-rationale` 等未验证建议能力的 fallback 策略。
- 完善 SOP 卡片 34-36，将任务拆解、验收标准和开发变更跟踪升级为 8 字段结构，并补齐对应 skill、子 Agent、Review Loop、Stage Gate 和下一阶段。
- 为 `development_tracking` 补齐 stage-router 映射，避免研发变更阶段缺少能力路由入口。
- 完善 SOP 卡片 37-40，将联调测试、上线准备、培训赋能和灰度试点升级为 8 字段结构，并补齐对应 skill、子 Agent、Review Loop、Stage Gate 和下一阶段。
- 为 `integration_qa` 和 `training_enablement` 补齐 stage-router 映射，完善上线准备主流程的能力路由。
- 完善 SOP 卡片 41-43，将上线监控、上线复盘和迭代规划升级为 8 字段结构，并补齐对应 skill、子 Agent、Review Loop、Stage Gate 和下一阶段。
- 为 `launch_monitoring` 和 `iteration_planning` 补齐 stage-router 映射，完成 44 张 SOP 卡片的 8 字段升级。
- 完成 44 张 SOP 卡片全量质检，确认 SOP 字段、canonical router、skill dependency registry、bundled skill index 和回归测试均通过。
- 同步 `stage-boundary-matrix.md` 与 `config/stakeholder-boundaries.yaml`，补齐方案探索、技术预检、合规预检、低保真原型、埋点、设计评审、研发变更、培训赋能、灰度和上线监控阶段的触发角色边界。
- 新增 SOP 全量质检报告 `outputs/product-crew-os-sop-full-quality-audit-v0.md`，记录通过项、已修正项、共享 artifact 设计和 Stage Gate 启发式警告。
- `SKILL.md`、能力地图、阶段 taxonomy 和 evolution loop 增加 Semantic Stage Router 入口，明确阶段误判应记录为 `stage_routing_feedback`，后续可接入轻量检索、embedding 或 RAG。

### 不变

- 不改变核心产品机制。
- 不改变记忆容器隔离规则。
- 不改变真实子 Agent 调用与模拟视角边界。

## v0.1.0-alpha - 2026-06-26

### 新增

- 初始 Product Crew OS skill 包。
- 单一可见 AI Product Coach 工作流模型。
- 默认主控教练 profile：`甜心教练-董董`，定位为魅力型领袖，性格思虑周全，亲和力拉满。
- 产品阶段分类和阶段流转规则。
- Stakeholder 边界矩阵和子 Agent 权限规则。
- 子 Agent 真实调用契约：`role_key`、persona、context packet、真实调用记录和模拟视角边界。
- 子 Agent 长期记忆 runtime 契约：角色记忆由 Project Workspace 管理，召唤前压缩注入，召唤后生成 memory delta。
- 有温度的新用户首启体验说明。
- 可配置的产品团队人格和团队风格 overlay。
- Artifact Workspace 模板。
- 真需求、弱需求、伪需求、未验证需求判断规则。
- Skill 路由和阶段路由参考。
- 覆盖完整 PM 流程的 Workflow SOP 库，定义每个细分阶段的输入、默认步骤、输出、干系人和过关标准。
- 用户自有 skill、常用软件和 MCP 可选适配规则。
- 能力地图、三种使用模式和自然语言触发语。
- 第三方 PM 能力包适配规则。
- Deep Artifact Pack、低保真原型、技术任务拆解和测试场景的最小模板。
- 原型增强路径：image 概念图 -> HTML Demo -> Pencil / Figma 可编辑原型。
- 产品进化与 checkpoint 规则。
- 回归测试场景。

### 调整

- 发布包将默认主控教练 profile 定义为可配置预设，而不是硬编码身份。
- 用户偏好和具体项目 workspace 不进入公共发布包。
- 明确区分真实子 Agent 调用和模拟角色视角；没有调用记录时不得声称“已拉起”。

### 不包含

- 真实项目 workspace。
- 用户偏好记忆。
- 具体项目中的客户访谈、PRD、会议纪要或决策记录。
- 支付、定价或 SaaS 商业化实现。

### 已知限制

- 本版本是可迁移规则包和 skill 包，不是完整 SaaS 产品。
- 外部工具和 MCP 适配器只作为可选建议，不是强依赖。
- Deep Artifact Pack、低保真原型、技术任务拆解和测试场景已经作为最小可编辑模板纳入当前能力；后续版本可以继续加深自动化和界面体验，但这些不是“未来才补”的能力。
- 补充 `validate-package.rb` 和 `run-regression.rb`，让 release 包可以本地验证场景登记、mock 子 Agent 调用、模拟视角降级和角色记忆注入。
- 移除公开 release 包中的内部测评记录，避免把运行时调用记录当作开源内容发布。
