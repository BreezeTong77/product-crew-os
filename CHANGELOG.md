# 变更日志

Product Crew OS 的重要变更都会记录在这里。

## v0.1.1 - 2026-06-27

### 优化

- 重写 README 首屏，让 GitHub 新访客先看到产品价值、适用人群和开始方式。
- 增加 badges、Start Here、可复制 prompt、Mermaid 工作流图和能力地图。
- 将复杂规则说明下沉到 docs 和 references，减少首屏阅读负担。
- 新增 `examples/first-run-demo.md` 和 `examples/prd-review-demo.md`。
- 明确本地质检命令和预期输出，方便用户 clone 后验证可用性。

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
