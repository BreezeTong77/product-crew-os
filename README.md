# Product Crew OS

[![Release](https://img.shields.io/badge/release-v0.1.3-blue)](releases/v0.1.3.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![SOP](https://img.shields.io/badge/SOP-44-orange)](product-crew-os-skill/references/workflow-sop-library.md)
[![Bundled Skills](https://img.shields.io/badge/bundled%20skills-49-orange)](product-crew-os-skill/references/bundled-skill-index.md)

面向产品经理的 Workflow-first AI 工作系统。

它不把产品工作变成一群 Agent 聊天，而是由一个主控教练带着用户推进：先判断当前该做什么，再命中 SOP、调用能力、沉淀项目文件；需要评审时，再拉对应角色进来。

```text
用户输入
-> 判断是否属于产品任务
-> Stage / SOP 路由
-> Skill 执行
-> Artifact Workspace
-> 必要时评审
-> 用户确认
-> Stage Gate 和下一步
```

## 适合什么场景

- 从想法开始，判断问题、机会和验证方式。
- 整理需求、确定 MVP、写 PRD、做评审。
- 把评审、决策、风险和下一步沉淀成可继续编辑的项目文件。
- 为团队接入自己的 SOP、Skill、角色模板或外部工具。

## 已包含什么

- 44 个产品工作 SOP：输入、动作、产物、评审和阶段门都有明确约定。
- 49 个随包 PM Skill：由 Router 选择，用户也可以用自己的 Skill 覆盖。
- 本地 Runtime：SQLite 记录项目、产物版本、评审、决策、事件和 Gate。
- Artifact Workspace：输出 Markdown、YAML、JSON 等可追溯项目文件，可作为 Obsidian Vault 打开。
- 评审契约：真实调用、模拟视角和运行时受限必须明确区分；没有完整 Context Packet、原始评审记录和运行 ID，不能作为 Gate 依据。
- RAG 证据约束：支持本地文本和图片资料接入；低置信 OCR、未授权或未索引来源不能作为 Gate 证据。

## 快速开始

安装或复制 `product-crew-os-skill/` 后，直接用自然语言开始：

```text
我有一个产品想法，先帮我判断值不值得做。
```

```text
我写完 PRD 了，帮我做一次内审。
```

```text
客户提了一个需求，帮我判断是真需求还是伪需求。
```

Product Crew OS 只处理产品工作或自身配置。翻译、闲聊、普通代码问题等，会在输入范围门退出，不强行进入 SOP。

## 真实边界

- 44 个 SOP 都有卡片、路由、测试样本和最小 Runtime 链路；这不等于 44 个 SOP 都已完成深度真实业务验证。
- 内置 Skill 被选中不等于已经真实执行。只有宿主返回执行证据，才算可用于 Gate 的执行。
- 子 Agent 是否能真实调用取决于宿主环境。不能调用时必须标记 `runtime_blocked` 或 `simulated`，不能冒充真实评审。
- OCR、Embedding、向量库和外部 MCP 都是本地可选能力。缺依赖时必须显示不可用，不能假装已接入。
- 项目材料、用户偏好和团队风格只进入独立 Project Workspace，不能写入公共规则包。

## 本地验证

在仓库根目录运行：

```text
ruby product-crew-os-skill/tests/validate-package.rb
ruby product-crew-os-skill/tests/run-regression.rb
ruby product-crew-os-skill/tests/run-runtime-smoke.rb
ruby product-crew-os-skill/tests/run-sop-e2e-smoke.rb
ruby product-crew-os-skill/tests/run-review-loop-e2e.rb
ruby product-crew-os-skill/tests/run-loop-50-cases.rb --release-gate
ruby product-crew-os-skill/tests/run-source-ingestion-runtime.rb
```

这些测试分别检查：发布包完整性、路由和规则、SQLite 写入、44 SOP 最小链路、评审门禁、50 条回归 case，以及本地资料接入。测试通过不代表线上用户效果。

## 关键文档

- [Skill 入口](product-crew-os-skill/SKILL.md)
- [44 SOP 库](product-crew-os-skill/references/workflow-sop-library.md)
- [Skill 索引](product-crew-os-skill/references/bundled-skill-index.md)
- [状态机与实现边界](product-crew-os-skill/references/workflow-implementation-coverage-v0.md)
- [子 Agent 调用契约](product-crew-os-skill/references/subagent-invocation-contract.md)
- [Runtime 使用说明](product-crew-os-skill/runtime/README.md)
- [v0.1.3 发布说明](releases/v0.1.3.md)

## 许可证

Product Crew OS 自有规则、模板、配置和测试按 [MIT License](LICENSE) 授权。

`product-crew-os-skill/third_party/skills/` 下的第三方 Skill 保留各自许可证；请查看 [THIRD_PARTY_NOTICES.md](product-crew-os-skill/THIRD_PARTY_NOTICES.md)。
