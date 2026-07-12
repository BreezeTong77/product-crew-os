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

## 1.1 LangGraph 控制平面

运行时统一使用 `runtime/pco_runtime.py`。它不是第二套会自己决定产品流程的 Agent，而是把既有的运行时契约固化成有状态的控制图：

```text
Input Scope Gate
-> Retrieval Evidence Guard
-> Stage / SOP Route
-> Skill Execution Guard
-> Artifact Writer
-> Review Packet Builder
-> External Review Interrupt
-> User Decision Interrupt
-> Project Memory Writer
```

- 图的 `thread_id` 是一次可恢复执行的身份；暂停后的 review callback 和用户决策必须恢复同一条线程，不能另起一条文本回合绕过前置节点。
- LangGraph checkpoint 只用于恢复图状态。Project SQLite / Project Workspace 才是 artifact、评审、决策和导出物的事实源。
- `interrupt()` 产生的等待状态不是 Gate 通过。只有后续节点验证证据后，才允许用户确认并写入 Gate 结果。
- 外部 delegate callback 除完整 Context Packet、`runtime_agent_id` 和 raw review 外，还必须带由私有 `PCO_LANGGRAPH_DELEGATE_SECRET` 生成的签名。仅传一个 runtime ID 不能证明真实调用。
- `runtime_nickname` 只能作审计元数据，不能覆盖已配置 `role_key`、`display_name` 或 persona；原始评审必须在 `raw-review-records` 可见。

Python adapter 覆盖 Coze、OCR/RAG 和 CLI；任何 adapter 都必须经 LangGraph 节点和同等级回归验证，不能建立旁路流程。

## 2. 标准回合写入链路

每个有意义的产品工作回合，都应按下面顺序写入：

```text
用户输入
-> Domain Gate
-> Stage Router
-> SOP Router
-> Skill Router
-> Skill Execution Contract
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

### 2.1 Runtime Preflight / 运行时预检

`record-turn` 不能相信主控或 Coze 传入的 `stage_id`、`sop_id`、`primary_skill` 或 `review_roles`。在写入 SOP、Skill、Artifact 和 Stage Run 前，runtime 必须先执行或验证 `route-intent`，并以持久化 route decision 为控制面真源：

```text
record-turn
-> route-intent
-> 写 routing/stage-route-decision.jsonl
-> 校验 product_crew_os_applies / stage_id / route_status / skill_status
-> 只创建待评审 / 待用户确认的 Stage Run
-> finalize-stage-gate（携带同一 stage_run_id）才可能 pass / conditional_pass
```

如果出现下列任一情况，runtime 可以继续保存草稿 artifact 和审阅痕迹，但 Stage Gate 必须降级为 `blocked_runtime_preflight`：

- 没有 route trace。
- `route-intent` 判断为非产品任务。
- route 结果仍为 `needs_clarification`。
- route `stage_id` 与 `record-turn` 传入 stage 不一致。
- route `sop` 与传入 SOP 不一致，或传入 Skill 不是 route primary / fallback。
- 没有经验证的 Skill Execution Contract 与 execution receipt。
- Required / Triggered Roles 被调用方省略、设为 `none` 或用模拟评审替代。
- 标准用户运行要求真实 embedding，但 route decision 中 `real_embedding_performed != true`。
- 标准 SOP 要求真实子 Agent，但 Required / Triggered roles 没有真实 invocation。
- skill 执行状态为 `template_degraded`。

这条规则专门防止“Coze / 普通 Agent 生成了文档，但 SOP、skill、embedding、子 Agent 和 runtime 都没接上”的假通过。

本地 runtime 可用以下环境变量开启硬门禁：

```bash
PCO_STAGE_ROUTER_EMBEDDING=real
PCO_REQUIRE_REAL_EMBEDDING=1
PCO_REQUIRE_REAL_SUBAGENTS=1
```

`PCO_STAGE_ROUTER_EMBEDDING=real` 会调用本地开源 BGE provider 对 44 SOP prompt-eval set 建立实时 embedding top-K 召回。TF-IDF、关键词、local hash dry-run 只能作为 smoke，不得写成 real embedding。

Python / LangGraph 本地命令入口是：

```bash
python3 product-crew-os-skill/runtime/pco_runtime.py record-turn \
  --workspace ./runtime-workspace \
  --project-id demo \
  --user-input "先做 MVP，帮我砍范围" \
  --thread-id demo-mvp-001 \
  --skill-execution-json '{"skill_id":"scope-cutting","execution_id":"host-run-001","output_ref":"artifacts/mvp-scope.md","execution_mode":"external_workflow","contract_valid":true,"may_change_stage":false,"may_decide_gate":false,"may_write_project_memory":false,"may_call_agents":false}'
```

`record-turn` 必须至少写入：

| 模块 | 写入内容 |
| --- | --- |
| `routing/stage-route-decision.jsonl` | route decision id、stage、candidate routes、retrieval mode、confidence |
| `sop_runs` | stage、sop、用户输入、路由置信度 |
| `skill_runs` | selected skill、fallback、执行状态、输出引用 |
| `artifacts` / `artifact_versions` | 可编辑产物与版本 |
| `review_sessions` | 结构化评审会、artifact 版本、参与角色、状态 |
| `context_packets` | 角色评审上下文包 |
| `agent_invocations` | 子 Agent 调用账本，区分真实和模拟 |
| `raw_review_records` | 每个角色的原始评审输出和证据 |
| `review_items` | 评审项与建议 |
| `events` | 指标事件 |
| `stages.stage_run_id` | 本轮不可变执行 ID；最终 Gate 必须锁定到它，不能按同 stage 的最新记录关闭 |
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

如果没有 `stage_route_decision`、有效 Skill execution receipt、完整 Required / Triggered Roles 的真实评审，或用户确认，任何 `conditional_pass` 都应视为无效。

### 2.2 Skill Execution Contract / 外部 Skill 执行契约

外部 Skill 可以保留自己的专业方法、推理链和文档工作流；Product Crew OS 不把它压缩成固定几步或固定格式。但正式执行必须带契约，防止 Skill 替代 SOP、Gate、用户决策或团队评审。

```text
SOP 选择 Skill 与目标
-> Contract 约束权限与证据
-> Skill 运行专业工作流
-> Runtime 校验实际动作与输出证据
-> Artifact / Review / 用户决策 / Stage Gate
```

契约至少声明：`skill_id`、`allowed_stage_ids`、`capability_scope`、`approved_actions`、实际 `observed_actions` 和输出证据。它不要求 Skill 使用固定 PRD 模板，但必须返回一个可归档 Artifact 名称和来源引用。

以下控制权始终属于 Product Crew OS，契约值必须为 `false`：

- `may_change_stage`
- `may_decide_gate`
- `may_write_project_memory`
- `may_call_agents`

外部工具动作可以在 `approved_actions` 中精确授权，例如 `figma.write_nodes`、`jira.create_issue`；未授权或禁止动作会令 `skill_contract_invalid`，通过类 Gate 自动降为 `blocked_runtime_preflight`。

示例见 [Skill Execution Contract 模板](../templates/skill-execution-contract.json)。

### 2.3 Codex Native Skill Contract

若宿主是 Codex，且路由目标是已打包的 `third_party/skills/*/SKILL.md`，它可作为 `host_native` 执行，不要求额外 LLM provider。有效证据为：Codex 实际加载的 `skill_path`、内容 hash、输入 Artifact/source refs、输出 Artifact/raw output ref 和执行时间。

`host_native` 仍受同一控制边界约束：Skill 不能自行改 Stage、决定 Gate、写项目记忆、召唤评审角色或写外部工具。MCP 写入仍须先征得用户授权。

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
python3 product-crew-os-skill/runtime/create_demo_vault.py \
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
