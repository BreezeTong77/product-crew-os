# 变更日志

Product Crew OS 的重要变更都会记录在这里。

## Unreleased

## v0.2.2 - 2026-07-12

### 真实执行与部署就绪门禁

- primary Skill 不再因输入不完整直接跳到无关 fallback：有辅助脚本但无法执行时，会读取同一份真实 `SKILL.md` 交给本机 Ollama 完成，仍由 LangGraph 签发回执。
- 44 SOP 检索改为图内 BGE 自己生成证据；调用方传入 `retrieval_evidence` 会被拒绝。新增 `rag-bootstrap`，未真的建立 44 SOP BGE 索引时，握手只能显示 `runtime_degraded`。
- Coze 子 Agent 私有绑定增加 `approved_runtime_agent_ids`。启用绑定后，签名回调还必须命中对应角色允许名单；重复、额外或模拟回调不能进入 Gate。
- 清理 Coze 蓝图、Docker、OpenAPI 和命令示例中的失效变量、旧接口名和旧的外部成功回传表述。

## v0.2.1 - 2026-07-12

### Graph-owned Skill execution

- `execute_skill` 成为 LangGraph 必经节点：SOP 命中后由图内执行 primary / fallback Skill，保存原始输出并生成签名回执。
- 调用方、Coze Bridge 和 CLI 不再接受自带 `skill_execution` 成功声明；伪造回执不能进入 Stage Gate。
- 执行器发现全部 49 份打包 Skill；脚本型能力直接执行，方法论 Skill 可通过已部署的本地 Ollama 读取真实 `SKILL.md` 后执行。
- 增加真实 Ollama 集成测试，验证 `mvp_scope -> shape-up -> 回执 -> Artifact` 链路。
- Coze OpenAPI、Workflow 蓝图、部署变量和审计表同步改为 graph-owned execution；MCP 仍要求真实连接与用户授权。

## v0.2.0 - 2026-07-12

### Python / LangGraph 全量迁移

- 删除 Ruby Runtime、Ruby Coze Bridge 和 Ruby 测试入口；发布包不再要求 Ruby。
- `pco_runtime.py` 成为唯一 Runtime CLI，`pco_coze_bridge.py` 成为唯一 HTTP Bridge。
- LangGraph 补齐项目上下文读取、评审收束、用户修订、Artifact 版本、定向复评和项目资产导出节点。
- 将本地 BGE、PaddleOCR / Tesseract、SQLite RAG 与受控 Skill 执行器迁入 Python adapter 层。
- Coze Docker 镜像改为 Python，Bridge 只允许进入 LangGraph `run` / `resume`，拒绝旁路评审或 Gate 写入。
- 发布测试迁为 Python：包校验、LangGraph E2E、Python adapter E2E 与 50 条 Release Gate。

### 真实边界

- 44 条 SOP 在 Release Gate 中验证 Stage / SOP / 主 Skill 路由与控制链；不等于 44 个外部 Skill 或子 Agent 均已真实线上执行。
- BGE 缺失时必须 `runtime_blocked`；hash 向量只能用于 smoke。
- 签名 delegate callback 是 adapter 契约夹具，不是线上子 Agent 证明。

## v0.1.4 - 2026-07-12

### LangGraph 控制平面

- 新增 LangGraph Runtime：`Input Scope Gate -> Retrieval Evidence Guard -> Stage/SOP Route -> Skill Execution Guard -> Artifact -> Review Interrupt -> User Decision Interrupt -> Project Memory`。
- 用 SQLite checkpoint 和稳定 `thread_id` 支持评审与用户决策的暂停 / 恢复；checkpoint 不是项目事实源，更不是 Gate 通过。
- 外部 delegate callback 增加签名验证：单独传 `runtime_agent_id` 不能作为真实调用证据；仍必须保留完整 Persona Context Packet 与 raw review。
- 新增 LangGraph 端到端契约测试，覆盖 44 SOP 路由、非产品退出、真实 embedding 辅助输入范围识别、无 Skill 证据阻塞、完整评审 packet、伪造 runtime ID 拦截、用户确认和真实 embedding 缺失阻塞。

### 迁移边界

- Ruby Runtime 暂保留为 Coze Bridge、OCR/RAG 和旧 CLI 的兼容 adapter。新控制逻辑优先写入 LangGraph；只有同等级回归验证后才替换旧 adapter。

## v0.1.3 - 2026-07-11

### 核心更新

- 收紧 Stage Gate：没有真实 Skill 执行证据、完整 Required 评审和用户确认，不能通过。
- 模板输出改为 `template_degraded`，不再可以伪装成 Skill 成功或通过 Gate。
- 路由决策、Required / Triggered 角色和 Stage Run 采用持久化控制面，调用方不能绕过既定边界。
- RAG 资料接入新增本地 OCR、来源元数据和 Gate evidence 绑定；不合格来源会阻塞最终 Gate。

### 文档调整

- README 保留主流程图、记忆隔离图、项目资产和真实调用边界，删除重复说明。
- 新增 `releases/v0.1.3.md`。

## v0.1.2 - 2026-07-05

### 发布定位

`v0.1.2` 是 Product Crew OS 的运行能力收口版：把“流程文档化”升级为“可追溯执行链路”，并把结构化评审、项目记忆与运行时落库统一收敛到可复现闭环。

### 新增

- 增加 Product Crew OS 领域意图门：先判断用户请求是否属于产品工作或 Product Crew OS 自身配置/维护，再进入 stage、SOP、Skill Router、子 Agent Review Loop 与 Stage Gate。
- 明确非产品请求不会被强行归入工作流；不会调用产品 skill、不会写入项目记忆，也不会召唤子 Agent。
- 新增 `non_product_task_exits_workflow` 回归场景，并让本地 regression runner 检查非产品任务不会误入产品工作流。
- 新增 Project Asset Pack 能力：定义项目资产包规则、Markdown/Obsidian-compatible 导出策略、项目首页、artifact 索引、时间线、决策日志、评审项、风险日志、下一步和导出清单模板。
- 新增 Project Memory Index Architecture：定义 SQLite/FTS/向量索引路线、数据库 CRUD、Obsidian 受控同步和长期记忆防覆盖机制。
- 新增最小本地 Runtime：基于 SQLite + Project Workspace 文件实现项目初始化、artifact 版本、决策、评审项、角色记忆、Context Packet、调用 ledger 和 Obsidian-compatible 导出，并新增 `run-runtime-smoke.rb` 验证真实写入链路。
- 新增 Runtime Adapter：`record-turn` 可将一次主控教练回合的 Stage、SOP、Skill、Artifact、Context Packet、调用 ledger、Review Item 与 Stage Gate 写入 SQLite。
- 新增 `run-sop-e2e-smoke.rb`：遍历 44 个 SOP prompt case，读取内置 skill，写入 `sop_runs`、`skill_runs`、artifact、context packet、invocation ledger 与 Obsidian 导出，验证 44 个 SOP 的最小端到端链路。
- 增强 Runtime 评估事件：`record-turn` 现在会写入 `stage_detected`、`skill_selected`、`memory_snapshot_built`、`agent_summoned`、`stage_gate_decision`，用于 Stage 命中率、Skill 命中率、记忆注入和评审发生率统计。
- 新增 `runtime/create_demo_vault.rb`，可为其他用户生成持久 SQLite、Project Workspace 与 Obsidian-compatible Vault，不再只依赖临时测试目录。
- 新增 `references/runtime-adapter-contract.md`，定义宿主环境如何把主控回合、子 Agent 调用、Artifact、评审项、记忆和评估事件写入 Runtime。
- 新增 `references/coze-runtime-blueprint.md` 与 `integrations/coze/workflow-blueprint.yaml`，描述 Coze 式主 Bot、子 Bot、workflow node、数据库表和导出插件的可实现形态。
- 更新 `agents/openai.yaml`：项目初始化后，产品工作回合应自动写入 Project Runtime；用户偏好、产品规则和真实团队材料仍需显式授权或维护动作。
- 新增 `templates/adapters/host-note-adapter-prompt.md`，提供不同宿主环境和 Markdown 笔记工具的可复制适配提示词。
- README 与 Runtime Adapter Contract 明确 Obsidian 只是默认示例，用户可自行适配 Logseq、Foam、Dendron、VS Code、Typora、Notion、飞书或通用 Markdown 文件夹。
- 引入结构化评审闭环：角色独立评审、冲突矩阵、复评范围收敛、用户决策可追溯。
- 外部材料反哺策略落地：同事邮件和会议截图先入 `source-ledger`，授权后更新角色风格记忆，避免污染当前上下文。

### 验证

- `ruby product-crew-os-skill/tests/validate-package.rb`
- `ruby product-crew-os-skill/tests/run-runtime-smoke.rb`
- `ruby product-crew-os-skill/tests/run-sop-e2e-smoke.rb`
- `ruby product-crew-os-skill/tests/run-regression.rb`
- `ruby product-crew-os-skill/tests/run-external-benchmark.rb`

### 不变

- 不改变核心产品机制。
- 不改变记忆隔离的三线并行规则。

### 已知限制

- 仍未内置完整可视化编排器，不同宿主环境仍需承载本地 Runtime 的主控实现。
- 对外集成采用建议化/可选适配，非强依赖。
- 外部基准通过的示例数据为本地与公开可复现样本，不替代真实生产流量评估。

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
