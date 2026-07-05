# Product Crew OS Runtime

这是 Product Crew OS 的最小可运行本地 Runtime。

它把规则包中的 Project Workspace、Project Asset Pack、团队记忆、Context Packet 和 Obsidian-compatible 导出落到真实文件与 SQLite 数据库中。

## 1. 当前能力

- 初始化项目：创建 SQLite 记录与项目工作区。
- 保存 artifact：写入 Markdown artifact、版本记录、artifact index 和 FTS 索引。
- 写入决策：写入 `decisions` 表和 `decision-log.md`。
- 写入评审项：写入 `review_items` 表和 `review-items.yaml`。
- 写入角色记忆：写入 `agent_memories`、`memory_deltas` 和 `agent-memory/{role}.md`。
- 构建 Context Packet：从 artifact、决策、评审、风险、角色记忆中生成子 Agent 上下文包。
- 记录真实/模拟子 Agent 调用：写入 `agent_invocations`。
- 记录主控回合：通过 `record-turn` 一次性写入 `sop_runs`、`skill_runs`、artifact、Review Session、Context Packet、调用 ledger、raw review record、review item 和 Stage Gate。
- 记录评估事件：写入 `stage_detected`、`skill_selected`、`memory_snapshot_built`、`agent_summoned`、`stage_gate_decision` 等事件。
- 导出 Obsidian Vault：按 10 大产品流程 + `_项目账本` + `_团队记忆` 生成可读 Markdown 项目包，其中 `_项目账本/review-sessions` 与 `_项目账本/raw-review-records` 用于查看评审全记录。

## 2. 产品级接入方式

Product Crew OS 的宿主环境应在项目初始化后，把每个有意义的产品工作回合写入 Runtime。

标准链路：

```text
Domain Gate
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
```

最低接入要求：

- 如果已经进入产品项目，主控回合结束时必须调用 `record-turn`。
- 如果召唤角色，必须调用 `build-context-packet` 和 `record-invocation`。
- 如果进入正式评审，必须能找到 Review Session、raw review record、review item、decision log 和 artifact diff 的写入位置。
- 如果宿主没有真实子 Agent 能力，必须把 `real_invocation_performed` 写为 `false`，并在用户可见回复里标注“模拟角色视角”。
- 如果宿主支持真实子 Bot / delegation / workflow node，则应把真实子 Bot ID 写入 `runtime_agent_id`。

## 3. 最小运行示例

```bash
ruby product-crew-os-skill/runtime/pco_runtime.rb init-project \
  --workspace ./runtime-workspace \
  --db ./runtime-workspace/product-crew-os.sqlite3 \
  --project-id demo \
  --name "Demo Project"

ruby product-crew-os-skill/runtime/pco_runtime.rb save-artifact \
  --workspace ./runtime-workspace \
  --db ./runtime-workspace/product-crew-os.sqlite3 \
  --project-id demo \
  --name "MVP Scope" \
  --stage-id requirement_analysis \
  --sop-id sop_16_mvp_scope \
  --content "MVP scope draft"

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
  --artifact-content "MVP scope draft from runtime adapter" \
  --review-roles "Biz,Tech,Design" \
  --gate-status conditional_pass \
  --gate-result "MVP can prove one core hypothesis"

ruby product-crew-os-skill/runtime/pco_runtime.rb export-obsidian \
  --workspace ./runtime-workspace \
  --db ./runtime-workspace/product-crew-os.sqlite3 \
  --project-id demo \
  --output-dir ./runtime-workspace/obsidian-vault
```

## 4. 生成持久 Demo Vault

这条命令会生成可长期查看的 SQLite 数据库、Project Workspace 和 Obsidian-compatible Vault，不会像测试用例一样自动删除。

```bash
ruby product-crew-os-skill/runtime/create_demo_vault.rb \
  --output-dir ./runtime-demo-vault
```

输出结构：

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

## 5. 验证

```bash
ruby product-crew-os-skill/tests/run-runtime-smoke.rb
ruby product-crew-os-skill/tests/run-sop-e2e-smoke.rb
```

通过标准：

- SQLite 数据库被创建。
- `projects`、`artifacts`、`decisions`、`review_sessions`、`raw_review_records`、`review_items`、`agent_memories`、`context_packets` 至少各有一条记录。
- Project Workspace 中存在 artifact、decision log、review items、agent memory 和 context packet。
- Obsidian Vault 中存在 `00_项目首页.md`、`_项目账本/`、`_项目账本/review-sessions`、`_项目账本/raw-review-records` 和 `_团队记忆/`。
- 44 个 SOP prompt case 都能通过 `record-turn` 写入 `sop_runs`、`skill_runs`、artifact、Review Session、Context Packet、调用 ledger、raw review record 和 Obsidian 导出。
- 事件表中存在 `stage_detected`、`skill_selected`、`memory_snapshot_built`、`agent_summoned`、`stage_gate_decision`。

## 6. 事实源边界

当前 Runtime 的事实源顺序是：

```text
SQLite + Project Workspace files
-> FTS index
-> Obsidian-compatible export
```

Obsidian 是可视化和检索入口，不是唯一事实源。外部修改未来必须通过 diff review 和 memory delta 写回。
