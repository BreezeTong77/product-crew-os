# Project Asset Pack / 项目资产包

本文件定义 Product Crew OS 如何把用户从 0 到 1 推进项目过程中产生的关键产物、决策、评审、风险和下一步沉淀成可读、可查、可恢复、可导出的项目资产包。

## 1. 产品定位

Project Asset Pack 是 Product Crew OS 的项目级知识库形态。

它不是聊天记录归档，也不是 Obsidian 依赖。它是 Project Workspace 的用户可读层和导出层：

```text
Project Workspace = 运行时事实源
Project Asset Pack = 用户可读项目知识库
Obsidian / Notion / 飞书 / Word / Excel / PPTX / PDF / PNG = 可选导出目标
```

主控教练必须把项目推进中已经收束的关键内容写入项目资产包，避免重要产物只停留在聊天气泡中。

## 2. Source of Truth 规则

Product Crew OS 的唯一事实源仍然是 Project Workspace：

- `project-state.json`
- `artifact-index.yaml`
- `timeline.md`
- `decision-log.md`
- `review-sessions/`
- `raw-review-records/`
- `review-items.yaml`
- `risk-log.md`
- `next-actions.md`
- `conflict-matrix.md`
- `open-questions.md`
- `artifact-diff.md`
- `source-ledger.md`
- `agent-memory/`
- `event-log.jsonl`
- `checkpoints/`

Obsidian-compatible Vault、Markdown ZIP、Word、Excel、PPTX、PNG、PDF、Notion、飞书文档都是导出或镜像，不反向替代 Project Workspace。

Machine-checkable contract:

- Project Workspace remains source of truth.
- Markdown project package is the default portable form.
- Obsidian-compatible export is optional.
- artifact index, timeline, decision log, review sessions, raw review records, review items, conflict matrix, open questions, artifact diff, risk log, next actions, source ledger, event log, checkpoints, and export manifest are the core project asset surfaces.

## 3. 应沉淀什么

默认沉淀：

- 阶段性 artifact：项目卡、问题定义、调研计划、MVP 范围、PRD、上线清单、复盘。
- 已收束评审：review summary、accepted/rejected items、decision log。
- 评审全记录：review session、原始角色评审、冲突矩阵、用户决策和复评结果。
- 阶段门结果：通过、条件通过、未通过、回退原因。
- 项目时间线：关键推进节点、阶段变化、重要产物版本。
- 下一步：owner、deadline、依赖、阻塞。
- 来源台账：关键结论来自哪个 artifact、会议纪要、评审或用户确认。
- 事件日志：重要写入、导出、阶段门变化和回滚事件。
- checkpoint：阶段通过、关键产物定版、评审收束后的恢复点。
- 角色项目记忆摘要：各角色在本项目中的关注点、历史 objection、已解决/未解决问题。

### 外部材料反哺样例（邮件截图 / 纪要截图 / 客户通信）

同事邮件截图、会议纪要截图、客服对话这类外部材料不直接写入当前会话上下文，也不写入角色的长期原文记忆。标准沉淀路径：

- `source-ledger.md`：先写 `source_ref`（来源、时间、置信度、脱敏范围）；
- `decision-log.md` / `review-items.yaml`：该材料作为依据时，记录关联的决策与争议；
- `project-state.json`：补充本次引用的 `evidence_refs`（引用索引），不写全文；
- `agent-memory/{role}.md`：仅在用户授权后，写“语气/偏好/常见卡点”等可复用摘要。

默认不沉淀：

- 全量聊天记录。
- 全量会议或访谈原文。
- 同事/客户原话全文。
- 用户偏好记忆。
- Product Rule Memory。
- 未确认的模型猜测。
- 子 Agent 的过程性发言全文。
- 敏感资料原文。

敏感材料如需保存，只能保存摘要、来源索引、权限说明和用户确认后的引用。

## 4. 写入触发器

主控教练在以下事件后检查是否需要更新项目资产包：

| Trigger | 写入动作 |
| --- | --- |
| Project Created | 创建项目目录、`project-state.json`、`project-home.md`、`artifact-index.yaml` |
| Artifact Created | 写入 artifact，并更新 `artifact-index.yaml` 与 `timeline.md` |
| Artifact Revised | 更新版本、状态、来源和修改摘要 |
| Review Opened | 创建 `review-session.md`，记录 artifact 版本、参与角色和 context packet 引用 |
| Review Closed | 更新 `timeline.md`、`decision-log.md`、`review-items.yaml`、`conflict-matrix.md`、`open-questions.md`、`artifact-diff.md`、`next-actions.md`、`export-manifest.yaml` 和对应 review artifact |
| Stage Gate Passed | 更新 `project-state.json`、`timeline.md`、`decision-log.md`、`next-actions.md` |
| Stage Gate Blocked | 更新 `risk-log.md`、`review-items.yaml`、`next-actions.md` |
| Agent Memory Delta | 更新 `agent-memory/{role_key}.md`，只写项目相关摘要 |
| User Export Requested | 生成 Markdown / Word / Excel / PPTX / PNG / PDF / Obsidian-compatible 导出包 |

## 5. 44 个 SOP 的沉淀策略

不是每个阶段都写全量文档，但每个阶段都至少更新状态、时间线或索引。

用户可见目录按 10 大产品流程组织，便于用户在 Obsidian 或通用 Markdown 阅读器里理解项目推进路径；44 个 SOP 不作为一级目录，而是写入每个 artifact 的 `sop_id`、标签、索引和事件日志，便于系统路由、检索和恢复上下文。

| 用户可见流程目录 | 覆盖 SOP 范围 | 默认沉淀 |
| --- | --- | --- |
| 01_机会发现 | 0-5 项目接入与机会发现 | 项目卡、现状流程、证据盘点、机会假设、时间线 |
| 02_用户研究 | 6-10 用户画像与调研 | 用户分层、访谈计划、问卷、样本、研究纪要、洞察摘要 |
| 03_问题定义 | 11-13 问题澄清与机会判断 | 问题陈述、JTBD、机会树、假设地图、真伪需求判断 |
| 04_需求分析 | 14-17 价值、优先级与范围 | 价值测算、优先级、MVP 范围、需求边界、取舍记录 |
| 05_方案设计 | 18-25 方案、流程、原型、指标 | 一页方案、可行性记录、流程图、低保真原型、指标、埋点 |
| 06_PRD与评审 | 26-33 PRD 与跨职能评审 | PRD 大纲、PRD、产品自审、设计/数据/技术/正式评审记录 |
| 07_交付规划 | 34-36 任务拆解与验收准备 | Epic / Story / Task、验收标准、排期、依赖、变更记录 |
| 08_上线准备 | 37-40 QA、上线、培训与灰度 | QA 场景、上线清单、培训 SOP、灰度计划、回滚预案 |
| 09_上线监控 | 41 上线监控 | 监控摘要、异常记录、指标观察、风险变化 |
| 10_复盘迭代 | 42-43 复盘与下一版规划 | 复盘、经验沉淀、下一版 backlog、roadmap update |

横向账本不归属于某一个阶段目录，必须放在 `_项目账本/` 中，因为用户常见查询是跨阶段的，例如“上次为什么这么决策”“技术负责人反对过什么”“下一步谁负责”“哪些风险还没关”。

| 横向账本 | 用途 |
| --- | --- |
| `artifact-index.yaml` | 所有 artifact 的 id、stage、sop、版本、状态和路径 |
| `timeline.md` | 项目推进时间线、阶段变化、关键里程碑 |
| `decision-log.md` | 已确认决策、理由、影响、验证点 |
| `review-sessions/` | 每次结构化评审会的对象、版本、角色和状态 |
| `raw-review-records/` | 每个角色的原始评审输出，按 review session 分组 |
| `review-items.yaml` | 子 Agent / 人类评审意见、状态、采纳与否 |
| `conflict-matrix.md` | 角色意见冲突、主控建议和用户决策 |
| `open-questions.md` | 缺证据、待确认、不能靠主控推断的问题 |
| `artifact-diff.md` | 根据评审修改 artifact 的版本差异 |
| `risk-log.md` | 风险、阻塞、owner、缓解方案 |
| `next-actions.md` | 下一步动作、负责人、截止时间、依赖 |
| `source-ledger.md` | 结论来源、会议/访谈/用户确认的引用位置 |
| `event-log.jsonl` | 写入、导出、阶段门、回滚等机器事件 |

条件沉淀：

- `request_triage` 只沉淀阶段判断和下一步，不沉淀混乱原话。
- `interview_guide` 可沉淀提纲，不沉淀联系人隐私。
- `compliance_precheck` 只沉淀风险摘要，不保存敏感细节。
- `development_tracking` 只沉淀里程碑和重要变更，不保存每日碎片。
- `launch_monitoring` 只沉淀监控摘要和关键事件，不保存全量日志。

## 6. Obsidian-compatible 导出

Obsidian 是可选阅读器，不是必装依赖。

默认导出为通用 Markdown 项目包；如果用户安装 Obsidian，可以直接把导出目录作为 Vault 打开。

建议目录：

```text
Product Crew OS Vault/
  Projects/
    {project-name}/
      00_项目首页.md
      01_机会发现/
      02_用户研究/
      03_问题定义/
      04_需求分析/
      05_方案设计/
      06_PRD与评审/
      07_交付规划/
      08_上线准备/
      09_上线监控/
      10_复盘迭代/
      _项目账本/
        artifact-index.yaml
        timeline.md
        decision-log.md
        review-sessions/
        raw-review-records/
        review-items.yaml
        conflict-matrix.md
        open-questions.md
        artifact-diff.md
        risk-log.md
        next-actions.md
        source-ledger.md
        event-log.jsonl
      _团队记忆/
        biz.md
        tech.md
        design.md
        qa.md
        data.md
        cs.md
        customer.md
      _导出/
        word/
        pdf/
        release-notes/
```

每个导出文件必须保留 frontmatter：

```yaml
project_id:
artifact_id:
stage_id:
status: draft | reviewed | approved | archived
source_of_truth: Product Crew OS Project Workspace
last_synced_at:
confidence:
```

## 7. 检索与上下文控制

未来可用于轻量检索、FTS、向量索引或 RAG，但运行时不能全量读取项目包。

正确方式：

```text
用户问题
-> 判断 stage / intent
-> 查 project-state.json
-> 查 artifact-index.yaml
-> 查 decision-log / review-items / risk-log
-> 编译短 Context Packet
-> 交给主控教练或子 Agent
```

禁止：

- 全量读取 Obsidian Vault。
- 把所有 Markdown 塞进 prompt。
- 把 rejected / superseded / archived 内容当作当前事实。
- 跨项目检索时忽略项目隔离和权限。

## 8. 过关标准

Project Asset Pack 功能过关时，应满足：

- 新项目能生成最小项目包结构。
- 每个实质 SOP 阶段会更新至少一个 asset 文件或状态索引。
- 每个 artifact 有 id、stage、版本、状态、来源。
- 每个 review item 有状态：open / accepted / rejected / deferred / resolved。
- 每个 decision 有背景、结论、理由、影响和验证点。
- 用户能一键导出 Markdown 项目包。
- Obsidian-compatible 只是导出格式，不是运行依赖。
