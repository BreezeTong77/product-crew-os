# Skill 与工具生态规则

## 1. 目的

Product Crew OS 需要覆盖完整产品流程，但不能把能力写死在少数 skill 或 MCP 上。

正确模型：

```text
产品阶段 -> 产物目标 -> skill / 用户自带 skill / artifact 模板 -> stakeholder review -> 用户常用软件输出
```

错误模型：

```text
只有安装了某几个 skill，Product Crew OS 才能工作。
```

## 2. Skill 是否足够

默认 skill registry 应覆盖主要产品阶段，并且发布包应内置一组可直接使用的第三方 PM skill，避免新用户部署后 SOP 卡片找不到能力。

- 项目接入。
- 商业分析。
- 证据盘点。
- 问题定义。
- 用户研究。
- JTBD。
- 机会树。
- 假设地图。
- 价值评估。
- 优先级排序。
- MVP 范围。
- 方案设计。
- 流程图。
- 原型。
- 指标。
- 埋点。
- PRD。
- 评审。
- 任务拆解。
- 验收。
- 上线。
- 复盘。

但 skill registry 永远不是最终答案。

规则：

- 有合适内置 skill，用内置 skill。
- 用户有更好的 skill，用用户的。
- 没有合适 skill，用 artifact 模板和主控教练判断做 v0。
- 发现长期缺口，再更新 registry。

内置能力的索引见 `bundled-skill-index.md`；第三方作者和许可证声明见 `../THIRD_PARTY_NOTICES.md`。

## 3. 用户自带 Skill

用户可能已经有自己的：

- Codex skill。
- 内部 PRD 模板。
- 调研模板。
- 评审 checklist。
- 任务拆解脚本。
- 指标口径模板。
- 公司内部流程规范。

接入前必须确认：

- skill 名称。
- 适用阶段。
- 输入。
- 输出。
- 是否会写外部系统。
- 是否包含敏感信息。
- 是否只用于当前项目，还是作为用户偏好长期保存。

保存规则：

- 当前项目使用：写入 Project Workspace。
- 用户长期偏好：写入 User Preference Memory。
- 公共产品规则：不得写入，除非完全脱敏、抽象、并经用户明确授权。

## 4. 每月 Skill 发现

Product Crew OS 可以提供“每月 skill 发现”能力。

触发方式：

- 用户主动要求。
- 用户开启月度推荐。
- 系统发现某个阶段长期缺少好 skill。

推荐来源：

- GitHub。
- Codex skill 社区。
- 用户指定仓库。
- 团队内部 skill 仓库。

推荐标准：

- 与 PM 工作流相关。
- 最近仍在维护。
- README 清楚。
- 输入输出明确。
- 权限和安全风险可解释。
- 不要求过度侵入用户环境。
- 能补齐当前工作流缺口。

推荐输出必须包含：

- skill 名称和链接。
- 适用阶段。
- 能解决什么问题。
- 与现有 skill 的关系：补充、替代、还是暂不建议。
- 安装风险。
- 是否需要用户授权安装。

禁止：

- 自动安装。
- 默认启用未知 skill。
- 把未经验证的 GitHub skill 写进公共产品规则。
- 因为 skill 新奇就推荐。

如果某个外部 skill 经过验证并适合成为默认能力，下一版可以将其复制到 `third_party/skills/`，同时补齐原作者、来源和许可证声明。

## 5. 用户常用软件优先

Product Crew OS 不能假设用户必须使用某个 MCP 或插件。

用户可能使用：

- 飞书。
- 企业 IM。
- Notion。
- Jira。
- Linear。
- TAPD。
- Confluence。
- Figma。
- Canva。
- Pencil。
- Excel。
- Google Docs。
- 内部系统。

规则：

- 先问用户常用软件。
- 再建议可选 MCP。
- 如果有 MCP，用 MCP 加速。
- 如果没有 MCP，提供可复制、可导入、可导出的中文 artifact。
- 不为了使用 MCP 而改变用户工作流。

### 5.1 原型生成路径

当用户要做原型时，主控教练应优先建议逐级增强，而不是直接跳到某个设计工具：

```text
原型目标与核心流程 -> image 概念图 -> HTML Demo -> Pencil / Figma
```

每一步的作用：

- image 概念图：快速探索视觉方向、布局气质和关键页面，不作为最终需求结论。
- HTML Demo：验证点击路径、页面状态、文案、交互反馈和演示效果。
- Pencil / Figma：在用户明确授权后，通过 MCP、插件或导入文件转成可编辑原型。

规则：

- 如果用户只需要低保真验证，可以停在页面状态表或 HTML Demo。
- 如果用户希望更高保真，建议先生成 image，再生成 HTML Demo，最后再对接 Pencil / Figma。
- 对接 Pencil / Figma 前必须说明目标工具、写入内容、影响范围和是否可撤回。
- 如果没有对应 MCP，也应提供可导入的 HTML、Markdown、截图说明或页面结构表。

## 6. MCP 的角色

MCP 是执行通道，不是产品主体验。

适合 MCP 的场景：

- 读取或更新外部文档。
- 创建设计文件。
- 导出 Word/PDF。
- 生成流程图。
- 写入任务系统。
- 同步会议纪要。

必须确认的场景：

- 创建任务。
- 修改外部文档。
- 发布内容。
- 发消息。
- 写入团队系统。
- 删除或覆盖文件。

如果用户常用软件没有 MCP：

- 产出 Markdown。
- 产出 CSV。
- 产出 Word/PDF。
- 产出 Mermaid。
- 产出 JSON/YAML。
- 产出可复制任务清单。

## 7. 主控教练话术

当用户问“这些 skill 够不够”时：

```text
够跑主流程，但不是封顶能力。
Product Crew OS 靠阶段和 artifact 运转，不靠固定几个 skill 硬撑。
现在这套 registry 覆盖主要 PM 流程；如果某个阶段没有合适 skill，我会先用模板和产品判断生成 v0。
如果你有自己的 skill 或团队模板，我可以把它接进当前项目或你的个人配置。
```

当用户问“能不能接我的软件”时：

```text
可以，但我不会默认强推某个 MCP。
你告诉我团队常用什么软件，我先按你的工作流输出。
有 MCP 时我可以建议用它加速；没有 MCP 时，我会给你可复制、可导入或可导出的 artifact。
```

当系统做月度 skill 推荐时：

```text
我可以每月帮你扫一轮 GitHub 和 skill 社区，只推荐能补齐你当前产品流程缺口的 skill。
我会先给你推荐理由和风险，不会自动安装。
```
