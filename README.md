# Product Crew OS

Product Crew OS 是面向产品经理工作的 AI Product Coach 规则包，也是一间有温度的 AI 产品办公室。

它不是可见的多 Agent 群聊，也不是通用 Agent 框架。它的核心是：

```text
Workflow + Skill + Review + Artifact Workspace
```

用户默认只和一个主控产品教练对话。主控教练负责判断产品工作阶段、调用合适 skill、按阶段 SOP 输出业务所需文件、在关键节点召唤必要的子 Agent 团队成员（如业务、研发、测试、设计、数据、法务、运营、客户成功或客户代表）、汇总评审意见，并把讨论沉淀为可继续编辑的产物，持续推进产品流程。

这些子 Agent 不是固定人格或群聊演员，而是一组可配置的产品同事：用户可以调整角色名称、性格、说话风格、评审严格度、参与边界，也可以用真实团队中的回复、邮件、会议纪要或评审意见，在授权后逐步强化团队风格。

发布版默认主控教练 profile 是：**甜心教练-董董**。人设是魅力型领袖，性格是思虑周全、亲和力拉满。这个 profile 是默认预设，不是硬编码身份；用户可以随时改主教练名称、性格、语气和推进力度。

本产品最重要的差异不是“有多少 skill”，而是让产品经理在混乱、孤独、被催、被质疑的时候，身边有一个会主动带路的教练和一支可配置的温暖产品团队：有人帮你追问证据，有人帮你挡住虚假范围，有人提醒真实客户和研发风险，最后把这些都变成下一步可执行的产物。

## 适合谁

- 刚入行或正在成长的产品经理。
- 想拥有专属 AI 产品团队的产品经理。
- 希望把产品流程、评审标准和项目记忆沉淀成可复用工作系统的人。

## 产品原则

- 单一可见主控教练，而不是多 Agent 群聊。
- 主控教练要温暖但有标准：先接住用户的混乱，再推动下一步可执行动作。
- 子 Agent 只在阶段门或评审需要时短暂进场，并且性格、语气、职责边界都可配置。
- 当运行环境支持真实子 Agent 调用时，主控教练必须真实调用并保留调用记录；没有真实调用时只能标注为模拟视角，不能声称已拉起。
- 子 Agent 聊天窗口本身不是长期记忆容器；长期记忆由 Project Workspace 管理，并在每次召唤时由主控教练压缩注入 context packet。
- 复杂讨论必须写入 Artifact Workspace。
- 用户可阅览产物默认使用中文。
- 产品规则、用户偏好、项目记忆必须分容器保存。
- 真实项目材料、同事回复、会议纪要和客户信息不得进入公共规则包。

## 当前版本

当前 release：`v0.1.0-alpha`

本版本重点提供：

- Product Crew OS skill 入口。
- 温暖主控教练与可配置产品团队体验。
- 阶段判断和 stakeholder 边界规则。
- 真伪需求判断规则。
- Artifact Workspace 模板。
- 团队角色和可定制人格配置。
- 默认主控教练 profile：甜心教练-董董，魅力型领袖，思虑周全，亲和力拉满。
- 覆盖完整 PM 流程的细颗粒 Workflow SOP 库。
- 用户自有 skill / 常用软件 / MCP 适配的规则说明。
- 每月 Skill 发现与推荐机制说明。
- 能力地图、使用模式和自然语言触发语。
- 第三方 PM 能力包适配规则。
- Deep Artifact Pack、低保真原型、技术任务拆解和测试场景的最小模板。
- 原型增强路径：image 概念图 -> HTML Demo -> Pencil / Figma 可编辑原型。
- 回归测试场景。

## 目录结构

```text
product-crew-os/
  README.md
  LICENSE
  CHANGELOG.md
  github-release-checklist-v0.md
  docs/
    product-rules.md
    portability-manifest.md
  releases/
    v0.1.0-alpha.md
  product-crew-os-skill/
    SKILL.md
    agents/
    config/
    references/
    templates/
    tests/
```

## 安装方式

把 `product-crew-os-skill/` 复制到 Codex skills 目录。

示例：

```text
~/.codex/skills/product-crew-os/
```

然后在 Codex 中调用：

```text
$product-crew-os
```

如果你的运行环境支持隐式 skill 调用，产品工作流相关请求也可以自动触发。

## 使用方式

你可以直接输入：

```text
我有一个产品想法，帮我判断值不值得做。
```

或：

```text
我写完 PRD 了，帮我做一次内审。
```

或：

```text
客户提了一个需求，帮我判断这是真需求还是伪需求。
```

Product Crew OS 会先判断当前产品阶段，再决定是否需要生成 artifact、召唤角色评审或补充证据。

## 本地质检

发布包内置最小回归检查。clone 后可以在仓库根目录执行：

```text
ruby product-crew-os-skill/tests/validate-package.rb
ruby product-crew-os-skill/tests/run-regression.rb --mock-delegate --check-only
```

预期输出：

```text
validate-package: PASS
run-regression: PASS
```

`validate-package.rb` 会检查配置、模板和回归场景是否齐全；`run-regression.rb` 会用 mock delegate 验证真实子 Agent 调用 ledger、模拟视角降级、memory_snapshot 和 memory delta 的最小闭环。

### 三种使用模式

| 模式 | 适合场景 | 示例 |
| --- | --- | --- |
| 单点能力调用 | 只想快速完成一个任务 | 帮我判断这个需求是真需求还是伪需求 |
| 完整工作流推进 | 从 0 到 1 跑一个产品或版本 | 帮我从一个想法走到 PRD |
| 中途插入 | 项目已经进行中，某个点卡住 | 我 PRD 写一半了，帮我看缺什么 |

你可以说自然语言，不需要先记住 skill 名称。

## 能力地图

| 分组 | 可以帮你做什么 |
| --- | --- |
| 项目接入 | 识别项目目标、用户、当前阶段和下一步 |
| 商业与战略判断 | 商业论证、价值评估、优先级排序 |
| 需求发现与验证 | 真伪需求判断、证据盘点、调研计划 |
| 用户理解 | 用户分层、JTBD、旅程地图 |
| 方案设计 | 方案对比、MVP 范围、一页方案 |
| 流程与原型 | 流程图、低保真原型、HTML Demo、Pencil/Figma 承接 |
| 数据与指标 | 北极星指标、指标树、埋点计划 |
| PRD 与评审 | PRD 草稿、产品自审、内部评审、正式评审 |
| 交付拆解 | Epic / Story / Task、验收标准、测试场景 |
| 上线与运营 | 上线清单、培训 SOP、灰度试点 |
| 复盘与迭代 | 上线监控、复盘、下一版 backlog |

每个能力分组背后都有可执行 SOP，不只是示例清单。SOP 会明确该流程需要什么输入、默认怎么推进、输出什么产物、该拉哪些干系人、什么条件算过关。

更完整的能力说明见：

- `product-crew-os-skill/references/capability-map.md`
- `product-crew-os-skill/references/workflow-sop-library.md`
- `product-crew-os-skill/references/stage-boundary-matrix.md`

## 可定制能力

用户可以配置：

- 用户显示称呼。
- 主控教练名称。
- 角色名称。
- 角色性格。
- 说话风格。
- 评审严格度。
- 角色参与边界。
- 子 Agent 团队是否更像真实公司里的同事风格。
- 用户自有 skill、模板、脚本或内部标准。
- 是否开启每月 Skill 发现与推荐。
- 常用软件偏好。
- MCP / 插件 / 外部工具的使用边界。

真实团队材料必须先确认用途和存储范围。

## Skill 与工具生态

Product Crew OS 不把能力固定死在少数几个内置 skill 上。

- 用户可以接入自己的 skill、模板、脚本、公司流程和内部标准。
- 内置 Skill 对用户应半透明可感知：默认不要求用户挑 skill，但要让用户知道当前正在使用商业论证、真伪需求判断、PRD 内审、技术预检等哪类能力。
- 高阶用户可以查看能力面板，了解内置 skill、用户自带 skill、适用阶段、启用状态和替代关系。
- 主控教练可以按月帮助用户发现 GitHub、Codex skill 社区或用户指定来源中的好用 skill，但只做推荐，不自动安装。
- 每条 Skill 推荐必须说明适用阶段、解决什么问题、为什么值得装、可能风险，以及是否替代现有 skill。
- 第三方 PM 能力包可以作为能力来源，但必须先映射到 Product Crew OS 阶段，不能整包吞并或强制用户记命令。
- 快捷触发语可以作为高阶入口，但必须回到主控教练驱动的同一套 workflow。
- MCP、插件和外部工具只是执行通道，不是产品主体验。
- 主控教练应先问用户常用软件，再建议 MCP；如果没有合适 MCP，也要输出可复制、可导入、可导出的中文 artifact。
- MCP 对用户必须显性授权：读取、写入、发消息、建任务、改文档前，都要说明要做什么、写到哪里、影响什么。
- 任何外部系统写入、发布、发消息、建任务、改文档，都必须先让用户确认。

## 记忆边界

Product Crew OS 使用三类记忆容器：

| 容器 | 内容 | 是否可进入开源包 |
| --- | --- | --- |
| Product Rule Memory | 通用产品机制、workflow、stage gate、artifact 规则 | 可以 |
| User Preference Memory | 用户称呼、主控名称、个人语气偏好 | 不可以 |
| Project Workspace Memory | 具体项目 PRD、访谈、评审、决策 | 不可以 |

发布到 GitHub 时，只应包含 Product Rule Memory。

子 Agent 的长期记忆不依赖底层子代理窗口自己保存。Product Crew OS 应把每个角色在项目中的历史关注点、上次卡点、采纳/拒绝建议写入独立项目 workspace，并在下次召唤该角色时注入压缩后的 `memory_snapshot`。

## 发布隐私要求

不要提交：

- 真实项目 workspace。
- 真实 PRD。
- 用户访谈。
- 会议纪要。
- 客户或同事材料。
- 用户个人偏好。
- API key、token、本地日志。
- 自动化或工具调用记录。

## 许可证

本项目使用 MIT License。见 [LICENSE](LICENSE)。

## 当前能力

`v0.1.0-alpha` 不是只发布空规则。首版必须具备可跑通产品经理全流程的最小能力，包括：

- Deep Artifact Pack。
- 低保真原型，并支持 image 概念图 -> HTML Demo -> Pencil / Figma 的逐级增强路径。
- 技术任务拆解。
- PM skill 适配。
- 测试场景。

这些能力在 alpha 版中以规则、路由和可编辑模板形式内置。后续版本可以继续增强模板深度、UI 呈现、自动化执行和外部工具集成，但不能把这些能力视为可有可无的未来项。
