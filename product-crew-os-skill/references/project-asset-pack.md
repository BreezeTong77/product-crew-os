# Project Asset Pack / 项目资产包

本文件定义 Product Crew OS 如何把用户从 0 到 1 推进项目过程中产生的关键产物、决策、评审、风险和下一步沉淀成可读、可查、可恢复、可导出的项目资产包。

## 1. 产品定位

Project Asset Pack 是 Product Crew OS 的项目级知识库形态。

它不是聊天记录归档，也不是 Obsidian 依赖。它是 Project Workspace 的用户可读层和导出层：

```text
Project Workspace = 运行时事实源
Project Asset Pack = 用户可读项目知识库
Obsidian / Notion / 飞书 / Word / PDF = 可选导出目标
```

主控教练必须把项目推进中已经收束的关键内容写入项目资产包，避免重要产物只停留在聊天气泡中。

## 2. Source of Truth 规则

Product Crew OS 的唯一事实源仍然是 Project Workspace：

- `project-state.json`
- `artifact-index.yaml`
- `timeline.md`
- `decision-log.md`
- `review-items.yaml`
- `risk-log.md`
- `next-actions.md`
- `source-ledger.md`
- `agent-memory/`
- `event-log.jsonl`
- `checkpoints/`

Obsidian-compatible Vault、Markdown ZIP、Word、PDF、Notion、飞书文档都是导出或镜像，不反向替代 Project Workspace。

Machine-checkable contract:

- Project Workspace remains source of truth.
- Markdown project package is the default portable form.
- Obsidian-compatible export is optional.
- artifact index, timeline, decision log, review items, risk log, next actions, source ledger, event log, checkpoints, and export manifest are the core project asset surfaces.

## 3. 应沉淀什么

默认沉淀：

- 阶段性 artifact：项目卡、问题定义、调研计划、MVP 范围、PRD、上线清单、复盘。
- 已收束评审：review summary、accepted/rejected items、decision log。
- 阶段门结果：通过、条件通过、未通过、回退原因。
- 项目时间线：关键推进节点、阶段变化、重要产物版本。
- 下一步：owner、deadline、依赖、阻塞。
- 来源台账：关键结论来自哪个 artifact、会议纪要、评审或用户确认。
- 事件日志：重要写入、导出、阶段门变化和回滚事件。
- checkpoint：阶段通过、关键产物定版、评审收束后的恢复点。
- 角色项目记忆摘要：各角色在本项目中的关注点、历史 objection、已解决/未解决问题。

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
| Review Closed | 更新 `timeline.md`、`decision-log.md`、`review-items.yaml`、`next-actions.md`、`export-manifest.yaml` 和对应 review artifact |
| Stage Gate Passed | 更新 `project-state.json`、`timeline.md`、`decision-log.md`、`next-actions.md` |
| Stage Gate Blocked | 更新 `risk-log.md`、`review-items.yaml`、`next-actions.md` |
| Agent Memory Delta | 更新 `agent-memory/{role_key}.md`，只写项目相关摘要 |
| User Export Requested | 生成 Markdown / Word / PDF / Obsidian-compatible 导出包 |

## 5. 44 个 SOP 的沉淀策略

不是每个阶段都写全量文档，但每个阶段都至少更新状态、时间线或索引。

| SOP 范围 | 默认沉淀 |
| --- | --- |
| 0-5 项目接入与机会发现 | 项目卡、现状流程、证据盘点、时间线 |
| 6-13 问题定义与用户理解 | 问题陈述、用户分层、调研计划、洞察、机会树、假设地图 |
| 14-25 价值、范围、方案与可行性 | 价值测算、优先级、MVP 范围、一页方案、可行性记录、流程图、原型、指标、埋点 |
| 26-33 PRD 与跨职能评审 | PRD 大纲、PRD、产品自审、评审记录、设计/数据/技术评审、正式评审决策 |
| 34-40 交付、验收与上线准备 | 任务拆解、验收标准、变更记录、QA、上线清单、培训 SOP、灰度试点 |
| 41-43 上线监控、复盘与迭代 | 监控摘要、复盘、下一版 backlog、roadmap update |

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
      00_Project_Home.md
      01_Project_Card.md
      02_Timeline.md
      03_Decision_Log.md
      04_Review_Items.md
      05_Next_Actions.md
      Artifacts/
      Reviews/
      Launch/
      Retro/
      Sources/
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
