# Project Memory Index Architecture / 项目记忆索引架构

本文件定义 Product Crew OS 在 Project Asset Pack 之上如何逐步加入 Obsidian、SQLite、全文搜索、向量检索和长期记忆防覆盖机制。

## 1. 核心原则

Product Crew OS 的事实源顺序如下：

```text
Project Workspace files
-> event-log.jsonl
-> SQLite / FTS / Vector index
-> Obsidian / Notion / Feishu / Word / PDF export
```

规则：

- Project Workspace 文件包是唯一事实源。
- 数据库是索引层和查询加速层，可从文件包和事件日志重建。
- Obsidian 是阅读器、浏览器和可选人工编辑入口，不是运行时事实源。
- 任何外部编辑都必须经过 import review，不能直接覆盖长期记忆。

## 2. 推荐数据库路线

| 阶段 | 存储 | 用途 | 适用状态 |
| --- | --- | --- | --- |
| M0 | Markdown / YAML / JSON / JSONL | 可读项目包、迁移、Git diff | 基础文件包 |
| M1 | SQLite + FTS5 | 本地结构化查询、全文搜索、轻量索引 | 当前 Runtime 已支持 |
| M2 | SQLite embedding table / LanceDB / Chroma | 语义检索、相似项目、相似决策 | 检索增强版 |
| M3 | Postgres + pgvector | 多用户、团队云端、权限与审计 | 团队版 |

建议先做 M1：SQLite + FTS5。

理由：

- 不增加用户部署成本。
- 可以随项目包一起迁移。
- 适合本地个人 PM 工作台。
- 可从 Markdown/YAML/JSON/JSONL 重建，避免数据库变成黑盒记忆。

## 2.1 当前 Runtime 落地状态

当前发布包已经提供最小本地 Runtime：

```text
product-crew-os-skill/runtime/
  db/schema.sql
  pco_runtime.rb
  create_demo_vault.rb
```

它支持：

- `init-project`：创建项目、工作区和 SQLite 记录。
- `record-turn`：将一次主控产品回合写入 SOP、Skill、Artifact、Context Packet、子 Agent 调用账本、Review Item、Stage Gate 和评估事件。
- `build-context-packet`：把角色记忆、当前 artifact、历史决策、开放评审项压缩成子 Agent 上下文。
- `record-invocation`：记录真实或模拟子 Agent 调用。
- `export-obsidian`：导出 10 大流程结构的 Obsidian-compatible Vault。

这意味着产品本身已经有可运行的项目记忆底座。真正能否“自动在每轮对话后写入”，取决于宿主是否把主控回合接到 Runtime Adapter。普通聊天环境需要手动或脚本触发；Coze、Dify、LangGraph 或自研应用可以把它做成 workflow node。

## 3. 最小表结构

SQLite 最小表：

```text
projects
artifacts
artifact_versions
decisions
review_items
risks
next_actions
sources
events
agent_memories
checkpoints
exports
```

可选检索表：

```text
fts_documents
embeddings
routing_feedback
```

字段原则：

- 每条记录必须有 `project_id`。
- 每条可追溯内容必须有 `source_ref`。
- 每条可变内容必须有 `version`、`status`、`updated_at`。
- 每条长期记忆必须有 `scope`，只能是 `project`、`user_preference` 或 `product_rule` 之一。
- 不把 raw transcript、raw chat log、private context packet 默认写入数据库。

## 4. CRUD 写入协议

所有写入必须通过 Project Memory Writer，不允许 Agent 随手覆盖文件或数据库。

### Create

```text
生成 memory delta
-> append event-log.jsonl
-> 写入 Markdown/YAML/JSON 文件
-> 更新 SQLite index
-> 可选更新 FTS / vector index
-> 生成 checkpoint（关键阶段）
```

### Read

```text
用户问题
-> 查 SQLite metadata / FTS / vector index
-> 命中 artifact_id / source_ref
-> 回读 Project Workspace 原文
-> 压缩为 Context Packet
```

数据库只返回候选，不直接作为最终事实。

### Update

```text
读取当前版本
-> 生成新版本或 patch
-> append event
-> 保留旧版本
-> 更新 artifact-index.yaml / database index
-> 写 checkpoint
```

默认不覆盖旧文件。PRD、方案、技术拆解等正式产物使用版本号。

### Delete

默认软删除：

```text
status = archived | superseded | rejected
```

禁止直接物理删除长期记忆。只有用户明确要求清除隐私/敏感内容时，才进入 hard delete 流程，并写入 deletion audit。

## 5. Obsidian 同步策略

### M0：只读导出

Product Crew OS 生成 Markdown 项目包，用户用 Obsidian 打开。

特点：

- 最安全。
- 不需要解析用户手工修改。
- 不会污染长期记忆。

导出目录应采用“10 大产品流程 + 横向账本”的结构：

```text
Projects/{project-name}/
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
  _团队记忆/
  _导出/
```

设计原则：

- 10 大流程用于用户阅读和导航。
- 44 个 SOP 用 `sop_id`、frontmatter、`artifact-index.yaml` 和 `event-log.jsonl` 记录，不作为一级目录。
- `_项目账本/` 用于跨阶段查询，承载决策、风险、评审项、下一步和来源台账。
- `_团队记忆/` 只保存项目内角色记忆摘要，不保存用户偏好、产品规则或同事原话全文。
- `_导出/` 只放 Word、PDF、release notes 等导出物，不反向作为事实源。

### M1：受控导入

用户在 Obsidian 修改 Markdown 后，Product Crew OS 只做 diff scan：

```text
detect changed files
-> summarize diff
-> ask user which changes should be imported
-> create memory delta
-> update Project Workspace
```

未经确认，不写回长期记忆。

### M2：双向同步

只有当有稳定文件锁、版本冲突处理、审计日志和回滚能力后，才允许双向同步。

## 6. 防覆盖机制

必须同时具备以下机制：

| 机制 | 作用 |
| --- | --- |
| Append-only event log | 每次写入先留痕 |
| Versioned artifact | 正式产物不覆盖旧版本 |
| Soft delete | 删除变归档，不直接抹掉 |
| Source ledger | 每个结论知道从哪里来 |
| Checkpoint | 关键阶段可恢复 |
| Content hash | 检测外部编辑和冲突 |
| Scope isolation | 项目、用户偏好、产品规则不混 |
| Import review | 外部修改需用户确认后写回 |

## 7. 长期记忆更新流程

长期记忆只接受 delta，不接受整段聊天灌入。

```text
candidate memory
-> classify scope
-> check sensitivity
-> attach source_ref
-> user confirmation if needed
-> append event
-> update file source
-> update index
```

示例：

```yaml
memory_delta:
  scope: project
  target: agent-memory/Tech.md
  source_ref: review-items.yaml#RI-12
  summary: "Tech role is concerned about API ownership and rollback plan."
  confidence: confirmed
  retention: project_lifetime
```

## 8. 查询与上下文控制

查询时不能把整个 Obsidian Vault 或项目包塞进上下文。

推荐流程：

```text
query
-> route intent
-> retrieve top candidates
-> read source files
-> summarize into Context Packet
-> answer or invoke sub-agent
```

当用户查询“某个阶段的材料”时，优先读取对应 10 大流程目录下的 artifact 索引和最新版文件；当用户查询“为什么这么定、谁反对、风险还剩什么、下一步做什么”时，优先读取 `_项目账本/`，而不是遍历阶段目录。

上下文包应包含：

- 当前 stage。
- 相关 artifact 摘要。
- 关键决策。
- 未解决 review items。
- 风险。
- 来源引用。
- 本轮允许判断的范围。

## 9. 产品路线建议

| 版本 | 能力 |
| --- | --- |
| v0.1.x | Markdown 项目包、Project Asset Pack、Obsidian-compatible 导出 |
| v0.2.x | SQLite + FTS5 本地索引、项目内全文搜索、最小本地 Runtime |
| v0.3.x | Embedding / vector index、相似项目和相似决策检索 |
| v0.4.x | Obsidian 受控导入、diff review、memory delta 写回 |
| v0.5.x | 多项目长期记忆、用户偏好检索、团队风格检索 |
| v1.0 | 团队版数据库、权限、审计、多人协作 |

## 10. 不做什么

当前阶段不建议：

- 一开始就上云数据库。
- 让数据库替代 Markdown 事实源。
- 让 Obsidian 双向自动同步。
- 把所有聊天记录都向量化。
- 把用户偏好、项目记忆和产品规则混在同一个索引里。
- 未经用户确认，把同事邮件、会议转录、客户原话写入长期记忆。

## 11. 当前最小 Runtime 实现

当前发布包已经包含最小本地实现：

```text
runtime/db/schema.sql
runtime/pco_runtime.rb
tests/run-runtime-smoke.rb
tests/run-sop-e2e-smoke.rb
```

已实现能力：

- SQLite schema：projects、artifacts、artifact_versions、decisions、review_items、agent_memories、memory_deltas、context_packets、agent_invocations、events、fts_documents。
- Project initialization：创建项目记录、项目工作区和基础账本文件。
- Artifact versioning：保存 artifact、写入 version、计算 content hash、更新 artifact index。
- Review / decision / memory writes：写入数据库并同步 Markdown/YAML 账本。
- Context Packet builder：从 artifact、决策、评审项、风险和角色记忆生成子 Agent 上下文包。
- Invocation ledger：记录真实或模拟子 Agent 调用。
- Runtime adapter：`record-turn` 将一次主控教练回合的 Stage、SOP、Skill、Artifact、Context Packet、调用记录、Review Item 和 Stage Gate 写入 SQLite。
- Obsidian export：生成 10 大产品流程目录、`_项目账本/` 和 `_团队记忆/`。
- Runtime smoke test：验证 SQLite 写入、并发写入 timeout、Context Packet 和 Obsidian 导出。
- SOP e2e smoke test：遍历 44 个 SOP prompt case，读取本地内置 skill，写入 `sop_runs`、`skill_runs`、artifact、context packet、invocation ledger 和 Obsidian 导出。

这仍不是完整云端产品，但已经把 Product Crew OS 从纯规则包推进到可执行本地 Runtime。
