# Runtime Adapter Contract / 运行时适配契约

本文件定义 Product Crew OS 在不同宿主环境中的真实运行方式。目标是让用户部署后，产品本身就能写入项目记忆、Artifact、评审项、Context Packet、事件指标和 Obsidian-compatible 项目包，而不是只停留在对话框描述。

## 1. 事实边界

Product Crew OS 开源包可以提供：

- 本地 SQLite Runtime。
- Project Workspace 文件包。
- Obsidian-compatible Markdown 导出。
- Note Adapter 抽象层，用于适配 Obsidian、Logseq、Foam、Dendron、VS Code、Typora、Notion、飞书或通用 Markdown 文件夹。
- Stage -> SOP -> Skill -> Review -> Artifact -> Memory 的写入协议。
- 真实子 Agent 调用前后的 Context Packet 与 Invocation Ledger。
- 对 Coze、Codex、Claude、Cursor 等宿主的适配蓝图。

Product Crew OS 不能单靠 Markdown 规则包强制任意宿主自动调用子 Bot。是否能“主控 Bot 自动调子 Bot”，取决于宿主是否提供 Bot 调用、workflow node、tool call、API、数据库或插件能力。

如果宿主没有真实子 Agent / delegation API，主控教练必须标注为“模拟角色视角”，并把 context packet、review item、decision 和 memory delta 写入 runtime。

## 2. 标准回合写入链路

每个有意义的产品工作回合，都应按下面顺序写入：

```text
用户输入
-> Domain Gate
-> Stage Router
-> SOP Router
-> Skill Router
-> Artifact Writer
-> Review Router
-> Review Session Writer
-> Context Packet Builder
-> Sub-agent Invocation Ledger
-> Raw Review Record / Review Item / Decision / Memory Delta
-> Stage Gate
-> Project Memory Writer
-> Obsidian / Markdown Export
```

本地命令入口是：

```bash
ruby product-crew-os-skill/runtime/pco_runtime.rb record-turn \
  --workspace ./runtime-workspace \
  --db ./runtime-workspace/product-crew-os.sqlite3 \
  --project-id demo \
  --stage-id mvp_scope \
  --macro-stage requirement_analysis \
  --sop-id mvp_scope \
  --user-input "先做 MVP，帮我砍范围" \
  --primary-skill scope-cutting \
  --fallback-skill shape-up \
  --artifact-name "mvp-scope.md" \
  --artifact-content "MVP scope draft" \
  --review-roles "Biz,Tech,Design" \
  --gate-status conditional_pass \
  --gate-result "MVP can prove one core hypothesis"
```

`record-turn` 必须至少写入：

| 模块 | 写入内容 |
| --- | --- |
| `sop_runs` | stage、sop、用户输入、路由置信度 |
| `skill_runs` | selected skill、fallback、执行状态、输出引用 |
| `artifacts` / `artifact_versions` | 可编辑产物与版本 |
| `review_sessions` | 结构化评审会、artifact 版本、参与角色、状态 |
| `context_packets` | 角色评审上下文包 |
| `agent_invocations` | 子 Agent 调用账本，区分真实和模拟 |
| `raw_review_records` | 每个角色的原始评审输出和证据 |
| `review_items` | 评审项与建议 |
| `events` | 指标事件 |
| Project Workspace | 项目首页、时间线、决策、评审、来源、团队记忆 |

## 3. 子 Agent 调用协议

真实子 Agent 调用必须满足：

```text
读取 role_key 对应 persona
-> 读取项目角色记忆
-> 读取当前 artifact、decision、risk、open review items
-> 构建 context packet
-> 调用宿主子 Bot / delegation API
-> 记录 agent_invocations
-> 收集评审输出
-> 写 raw_review_records / review_items / decisions / memory_deltas
```

如果宿主没有子 Bot 能力：

```text
仍然构建 context packet
-> 写 agent_invocations(real_invocation_performed=false)
-> 回答中标注“模拟角色视角”
-> 不声称真实召唤
```

## 4. 事件指标

Runtime 必须记录以下核心事件，便于回归和评估：

| 事件 | 用途 |
| --- | --- |
| `stage_detected` | 检查 Stage 命中率 |
| `skill_selected` | 检查 Skill 命中率和 fallback 情况 |
| `context_packet_built` | 检查是否为评审构建上下文 |
| `memory_snapshot_built` | 检查团队记忆是否被读取并注入 |
| `agent_summoned` | 检查子 Agent 是否真的调用或明确模拟 |
| `review_session_opened` | 检查正式评审是否绑定 artifact 版本 |
| `raw_review_record_written` | 检查原始角色评审是否可追溯 |
| `review_item_written` | 检查评审是否沉淀 |
| `decision_written` | 检查决策是否沉淀 |
| `stage_gate_decision` | 检查阶段门是否明确 |
| `obsidian_exported` | 检查可视化项目包是否导出 |

## 5. Note Adapter / 笔记工具适配

Obsidian 是当前默认示例，不是唯一支持目标。Product Crew OS 的项目包本质是 Markdown / YAML / JSON 文件夹，因此可以适配不同笔记工具。

推荐配置：

```yaml
note_adapter:
  type: obsidian | logseq | foam | dendron | vscode | typora | generic_markdown | notion | feishu
  output_dir: "./project-vault"
  structure: ten_product_flows
  link_style: wikilink | relative_path
  frontmatter: true
  tags: true
  source_of_truth: sqlite_plus_project_workspace
```

适配规则：

- Obsidian：推荐 `wikilink`、frontmatter、tag，用户用“打开本地文件夹作为 Vault”查看。
- Logseq：推荐 `wikilink`，可按 page / journal 结构扩展。
- Foam / Dendron / VS Code：推荐相对路径链接或 wikilink，保留 frontmatter。
- Typora / MarkText：推荐普通 Markdown 文件夹和相对路径链接。
- Notion / 飞书：作为导入或镜像，不作为事实源。

可复制提示词见 `templates/adapters/host-note-adapter-prompt.md`。

## 6. 持久 Obsidian 项目包

用户或宿主可以运行：

```bash
ruby product-crew-os-skill/runtime/create_demo_vault.rb \
  --output-dir ./runtime-demo-vault
```

输出：

```text
runtime-demo-vault/
  workspace/
    product-crew-os.sqlite3
    memory/projects/{project_id}/
  obsidian-vault/
    Projects/{project_name}/
      00_项目首页.md
      01_机会发现/
      02_用户研究/
      ...
      _项目账本/
      _团队记忆/
```

Obsidian 是阅读和检索入口，不是唯一事实源。事实源仍是 SQLite + Project Workspace 文件包。

## 7. 宿主适配要求

| 宿主能力 | 最低实现 | 增强实现 |
| --- | --- | --- |
| 文件系统 | 写 Project Workspace | Git diff / checkpoint / rollback |
| 数据库 | SQLite | Postgres / pgvector / 云数据库 |
| 子 Agent | 模拟角色视角并标注 | 调用真实 Bot / API / delegation |
| 工作流 | 主控教练按 SOP 执行 | 可视化 workflow nodes |
| 检索 | SQLite FTS | embedding / vector search / RAG |
| 可视化 | Markdown 文件夹 | Obsidian / Logseq / Foam / Dendron / Notion / 飞书 |

## 8. 是否达到 Coze 形态

如果运行在 Coze 这类有 Bot、workflow、database、plugin 的平台，可以实现：

- 主控 Bot 调用子 Bot。
- 子 Bot 通过 Context Packet 获得项目记忆。
- Workflow 节点读写数据库。
- Artifact 版本化。
- 用户导出 Obsidian-compatible 项目包。

如果运行在只支持普通聊天的环境，则只能实现规则、产物、项目包和模拟评审，不能假装拥有真实子 Bot 编排。
