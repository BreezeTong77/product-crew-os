# Product Crew OS - 可迁移运行清单

## 1. 一个 Markdown 文件够不够？

不够。

`product-crew-os-product-rules-2026-06-25.md` 可以让另一个聊天框理解产品理念和规则，但它只是“产品规则说明书”，不是完整可执行包。

另一个聊天框如果只拿到这个 md，大概率能模仿方向，但不能保证完整无差错地跑通，因为它缺少：

- 角色配置。
- 阶段边界。
- stakeholder 调用规则。
- artifact 模板。
- review item 状态机。
- project state 结构。
- context packet 模板。
- evolution 规则。
- 测试场景。

## 2. 最小可迁移包

要让另一个聊天框稳定复现今天搭建的产品机制，至少需要这一组文件：

```text
product-crew-os-skill/
  SKILL.md
  agents/openai.yaml
  config/
    crew-personas.yaml
    stakeholder-boundaries.yaml
    stage-transitions.yaml
    review-depth-policy.yaml
    agent-authority.yaml
    evolution-policy.yaml
  references/
    product-mission-vision-values.md
    target-users-and-core-pain.md
    demand-authenticity.md
    onboarding-customization.md
    stage-taxonomy.md
    stage-boundary-matrix.md
    skill-stage-router.md
    skill-and-tool-ecosystem.md
    subagent-context-packet.md
    subagent-natural-language.md
    gate-policy.md
    evolution-loop.md
    experience/
      first-run-demo.md
      human-centered-experience.md
      stage-rituals.md
      agent-customization-and-team-style.md
    open-source-release-notes.md
  templates/
    agent-context-packet.yaml
    project-state.json
    overlays/
      team-style-overlay.yaml
    artifacts/
  tests/
    scenarios/
```

其中：

- `SKILL.md` 是入口。
- `config/` 决定角色、边界、阶段和可靠性。
- `references/` 负责解释复杂规则、产品使命、目标用户和体验仪式。
- `templates/` 负责让产物可持续编辑。
- `tests/` 负责防止之后改坏。

## 3. 推荐迁移方式

如果只是让另一个聊天框理解方向：

```text
发送 product-crew-os-product-rules-2026-06-25.md
```

如果要让另一个聊天框按规则执行：

```text
发送整个 product-crew-os-skill 文件夹
并要求它先阅读 SKILL.md，再按需读取 config、references、templates
```

如果要发到 GitHub：

```text
发布 product-crew-os-skill/
附带 product-crew-os-product-rules-2026-06-25.md 作为产品设计说明
不要发布任何真实项目 workspace
```

## 4. 记忆容器隔离

Product Crew OS 必须把记忆分成三套容器。

### Product Rule Container

保存通用产品规则：

- workflow 规则。
- stakeholder 边界。
- artifact workspace 机制。
- review 状态机。
- skill routing。
- evolution 机制。

可以进入 GitHub。

### User Preference Container

保存用户个人偏好：

- 主控教练名称。
- 角色人格。
- 说话风格。
- 常用输出格式。
- 用户对自动化程度的偏好。

不进入公共 GitHub。

### Project Workspace Container

保存具体项目记忆：

- 项目背景。
- 具体 PRD。
- 具体评审意见。
- 具体决策。
- 项目干系人。
- 项目产物版本。

禁止进入产品规则包。

## 5. 迁移时的启动提示词

如果你把这套产品交给另一个聊天框，可以这样说：

```text
请把这套文件当作 Product Crew OS 的工作规则。

先阅读 SKILL.md。
然后读取 config/stakeholder-boundaries.yaml、config/crew-personas.yaml、config/stage-transitions.yaml。
再读取 references/product-mission-vision-values.md、references/target-users-and-core-pain.md。
当用户提出功能、客户、老板、销售、路线图或 PRD 需求时，读取 references/demand-authenticity.md，并先判断真需求、弱需求、伪需求或待验证需求。
当任务涉及新用户启动、阶段切换、评审进退场或真实团队风格时，读取 references/experience/ 下的体验规则。
当任务涉及复杂评审时，使用 templates/project-state.json 和 templates/artifacts/ 创建 Artifact Workspace。
当用户提供真实同事回复、邮件、会议转录或评审意见时，必须先确认用途和存储范围，再按需写入 templates/overlays/team-style-overlay.yaml 的用户/项目 overlay。

注意：
1. 产品规则、用户偏好、项目记忆必须分容器保存。
2. 不要把具体项目内容写入产品规则。
3. 子 Agent 只在边界允许的阶段出现。
4. 子 Agent 回复必须像真实同事，不要只说术语。
5. 聊天框只展示主控摘要，完整评审写入 Artifact Workspace。
6. 主控教练要在关键轮次给出项目状态栏、阶段门判断和下一步动作。
7. 角色名称、人格、语气、评审严格度和团队风格可以由用户定制，但真实团队材料不能进入公共产品规则。
8. 没有真伪需求判断，不进入 PRD、技术方案、排期或路线图承诺。
```

## 6. 结论

一个 md 文件适合传达理念。

完整跑通需要 skill folder + config + templates + tests。

真正可迁移的不是一段长提示词，而是一套结构化产品规则包。
