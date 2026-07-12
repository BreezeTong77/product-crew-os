# Product Crew OS Runtime

## LangGraph 主控链路（新默认）

从本版本开始，Product Crew OS 的新接入默认使用 LangGraph 作为控制平面：它负责每一步能否继续、何时暂停等待真实评审、何时等待用户确认，以及如何从相同 `thread_id` 恢复。

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

启动前安装依赖：

```bash
python3 -m venv .venv
.venv/bin/pip install -r product-crew-os-skill/runtime/requirements-langgraph.txt
```

初始化并运行：

```bash
python3 product-crew-os-skill/runtime/pco_langgraph_runtime.py init-project \
  --workspace ./runtime-workspace \
  --project-id demo \
  --name "Demo"

python3 product-crew-os-skill/runtime/pco_langgraph_runtime.py run \
  --workspace ./runtime-workspace \
  --project-id demo \
  --thread-id demo-run-001 \
  --user-input "我想做一个产品，第一步应该先做什么？"
```

当结果出现 `__interrupt__`，不是成功，也不是报错。宿主必须把其中的评审任务交给真实 delegate，或把用户决策展示给用户；随后用同一 `thread_id` 的 `resume` 恢复。外部 delegate 回调必须使用 `PCO_LANGGRAPH_DELEGATE_SECRET` 生成可验证签名，并保留完整 Persona Context Packet、runtime ID 和 raw review。没有这些证据，Gate 必须阻塞。

LangGraph checkpoint 只保存可恢复执行状态。项目事实、artifact、原始评审和 Obsidian 导出仍写入独立项目账本，不能把 checkpoint 当作业务审计记录。

详细命令见 [LangGraph Runtime](langgraph_runtime/README.md)。

## Ruby 兼容适配层

下方 Ruby Runtime 在迁移期继续保留，负责已有 CLI、Coze Bridge、OCR/RAG adapter 和历史回归测试。它不是新的 Stage Gate 主控；新能力应优先接入上方 LangGraph 图，再逐步替换对应 Ruby adapter。

它把规则包中的 Project Workspace、Project Asset Pack、团队记忆、Context Packet 和 Obsidian-compatible 导出落到真实文件与 SQLite 数据库中。

## 1. 当前能力

- 初始化项目：创建 SQLite 记录与项目工作区。
- 保存 artifact：写入 Markdown artifact、版本记录、artifact index 和 FTS 索引。
- 写入决策：写入 `decisions` 表和 `decision-log.md`。
- 写入评审项：写入 `review_items` 表和 `review-items.yaml`。
- 写入角色记忆：写入 `agent_memories`、`memory_deltas` 和 `agent-memory/{role}.md`。
- 构建 Context Packet：从 artifact、决策、评审、风险、角色记忆中生成子 Agent 上下文包。
- 记录真实/模拟子 Agent 调用：写入 `agent_invocations`。
- 路由留痕：通过 `route-intent` 写入 `routing/stage-route-decision.jsonl` 和 `stage_route_decision` 事件。
- 记录主控回合：通过 `record-turn` 先执行/验证 route trace，再写入 `sop_runs`、`skill_runs`、artifact 和待评审 Stage Run。默认 `standard_sop` 从持久化 route decision 反查 SOP、Skill 和 Required / Triggered Roles，只创建完整 Context Packet 并等待真实子 Bot 回调；它绝不直接通过 Stage Gate。模拟占位仅供显式测试，始终 `invalid_for_gate`。
- 执行外部 Skill：通过 `execute-skill` 或 Bridge 的 `/v1/skills/execute` 调用白名单 command driver。读取 `SKILL.md`、路由到 Skill 或返回模板都不算执行；方法论型和 MCP 型 Skill 没有真实宿主回调/工具账本时返回 `deployment_required`，并带 `must_notify_user=true`、部署步骤和是否需要写入授权。宿主必须先把提示展示给用户，不能把这类结果写成 `completed`。
- 记录评估事件：写入 `stage_detected`、`skill_selected`、`memory_snapshot_built`、`agent_summoned`、`stage_gate_decision` 等事件。
- 导出 Obsidian Vault：按实际写入的阶段分类目录 + `_项目账本` + `_团队记忆` 生成可读 Markdown 项目包。未执行阶段不会创建空目录；`_项目账本/review-sessions` 与 `_项目账本/raw-review-records` 用于查看评审全记录。

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

- 如果已经进入产品项目，主控回合结束时必须调用 `record-turn`。`record-turn` 会自动执行 `route-intent` 并写 route trace。
- 如果 route 结果为非产品任务、需要澄清、SOP / Skill 不一致、没有有效 Skill Execution Contract / execution receipt、漏 Required / Triggered Roles，或 skill 状态为 `template_degraded`，runtime 会阻塞 Gate。
- `record-turn` 只会返回 `awaiting_external_review`、`awaiting_user_decision` 或阻塞状态；只有 `finalize-stage-gate` 且带相同 `stage_run_id`、真实评审和用户确认时，才可能返回 `pass / conditional_pass`。
- 标准 SOP 用户运行建议开启：
  - `PCO_STAGE_ROUTER_EMBEDDING=real`
  - `PCO_REQUIRE_REAL_EMBEDDING=1`
  - `PCO_REQUIRE_REAL_SUBAGENTS=1`
- 如果召唤角色，必须调用 `build-context-packet` 和 `record-invocation`。
- 如果进入正式评审，必须能找到 Review Session、raw review record、review item、decision log 和 artifact diff 的写入位置。
- 如果宿主没有真实子 Agent 能力，必须把 `real_invocation_performed` 写为 `false`，并在用户可见回复里标注“模拟角色视角”。
- 如果宿主支持真实子 Bot / delegation / workflow node，则应把真实子 Bot ID 写入 `runtime_agent_id`。

## 3. Coze 真实接入

`references/coze-runtime-blueprint.md` 和 `integrations/coze/workflow-blueprint.yaml` 只是设计说明；要让 Coze 真正运行 Product Crew OS，必须启动 `pco_coze_bridge.rb` 并把 `integrations/coze/runtime-plugin-openapi.yaml` 导入为 Coze API 插件。

启动 Bridge：

```bash
export PCO_RUNTIME_TOKEN="replace-with-a-long-random-secret"
export PCO_RUNTIME_BIND="0.0.0.0"
export PCO_RUNTIME_PORT="8787"
export PCO_RUNTIME_WORKSPACE="/srv/product-crew-os/workspace"
export PCO_RUNTIME_EXPORT_ROOT="/srv/product-crew-os/exports"
export PCO_STAGE_ROUTER_EMBEDDING="real"
export PCO_REQUIRE_REAL_EMBEDDING="1"
export PCO_REQUIRE_REAL_SUBAGENTS="1"
export PCO_COZE_SUBAGENT_DELEGATE="workflow_callback"

ruby product-crew-os-skill/runtime/pco_coze_bridge.rb
```

运行时服务必须部署到 Coze 能访问的 HTTPS 域名。不要把 `127.0.0.1`、token 或真实子 Bot ID 放进公开仓库。

Coze Workflow 的强制顺序：

```text
Capability Handshake
-> /v1/routes
-> Coze route trace database mirror
-> Skill Execution
-> /v1/turns
-> Coze Sub Bot Delegate
-> /v1/reviews/callback
-> Coze review database mirror
-> user decision
-> /v1/gates/finalize
-> /v1/exports/obsidian
```

`/v1/turns` 必须带先前 `/v1/routes` 返回的 `route_decision_id`。Runtime 从这个不可变决策中派生评审角色，忽略调用方试图传入的 `review_roles`；它只创建 Review Session 和完整人格 Context Packet，**绝不预写模拟评审或通过 Gate**。`/v1/gates/finalize` 必须带 `stage_run_id`，并且只有同时拿到 route trace、有效 Skill execution receipt、真实 `runtime_agent_id`、完整 packet、raw review 和用户确认时，才可能返回 `pass` 或 `conditional_pass`。

Coze 资产：

- `integrations/coze/runtime-plugin-openapi.yaml`：导入 API 插件。
- `integrations/coze/sub-bot-bindings.example.yaml`：复制为私有配置后绑定真实子 Bot ID。
- `integrations/coze/database-schema.yaml`：在 Coze Database 创建可审计镜像表。
- `integrations/coze/workflow-node-map.yaml`：按节点顺序连接，不允许 LLM 节点自行放行 Stage Gate。

Bridge 的 `/v1/routes` 不再只是临时算一次 44 SOP 相似度：在真实 embedding 模式下，它会把 `pco_rules` 的 44 SOP 批量写入 `embedding_documents` / `embedding_chunks`，用内容哈希跳过未变更来源，并把每次查询写进 `embedding_retrieval_events`。架构目标是 `sqlite-vec`；当前发布包检测到扩展未连接时，Runtime 会明确返回实际引擎 `sqlite_json_cosine_fallback`，仍做持久向量存储和余弦检索，但不会把它伪称为 `sqlite-vec`。

`/v1/rag/ingest` 的 HTTP Bridge 只接收已经由 Coze 文件解析或 OCR 节点抽出的文本，避免远程请求读取 Runtime 主机上的任意文件；本地 CLI 才可以传入 `--file_path`，由 Runtime 实际调用 PaddleOCR 或 Tesseract。OCR 没有真实引擎、缺少语言包或返回空文本时会返回 `runtime_blocked`，不会入库。`pco_rules` 可直接写入；项目、用户偏好和团队风格等私有 namespace 必须带 `consent_ref`，否则 Runtime 拒绝写入。

当 artifact 实际引用 RAG 来源作为阶段门证据时，工作流必须调用 `/v1/rag/evidence` 绑定 `stage_run_id + artifact_id + source_ref`。OCR 置信度低于阈值、私有材料没有完成 PII 分类、或来源不在索引中，都会被标为不可用并阻止最终 Gate；普通检索本身不会自动变成 Gate 证据。

### 本地 OCR 部署

图片和截图的本地 OCR 是可执行 adapter，但 PaddleOCR / Tesseract 是宿主依赖，不会被包装成“已随仓库安装”。推荐执行：

```bash
bash product-crew-os-skill/runtime/setup-local-ocr.sh
```

脚本把开源 PaddleOCR 安装到 `~/.local/share/product-crew-os/ocr-env`；`SourceExtractor` 会自动发现该路径。部署后可用真实但不含敏感信息的截图验证：

```bash
PCO_OCR_SMOKE_SOURCE=/absolute/path/to/screenshot.png \
  ruby product-crew-os-skill/tests/run-source-ingestion-runtime.rb
```

没有 OCR 引擎时，测试和 Runtime 必须返回 `runtime_blocked_missing_ocr_engine`。没有提供 `PCO_OCR_SMOKE_SOURCE` 时，即使引擎已安装，测试也只报告“引擎可用、未做真实样本抽取”，不会虚报真实 OCR 成功。

本地 HTTP 合约测试：

```bash
ruby product-crew-os-skill/tests/run-coze-runtime-bridge-smoke.rb
```

这个测试使用受控回调载荷验证 Bridge 的拒绝和持久化逻辑，不代表已经在某个 Coze 空间完成线上部署；线上验收必须看到真实 Coze `runtime_agent_id`、Coze Database 行和 Runtime 产出的项目账本。

## 4. 最小运行示例

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
  --review-mode standard_sop \
  --gate-result "MVP can prove one core hypothesis"

ruby product-crew-os-skill/runtime/pco_runtime.rb export-obsidian \
  --workspace ./runtime-workspace \
  --db ./runtime-workspace/product-crew-os.sqlite3 \
  --project-id demo \
  --output-dir ./runtime-workspace/obsidian-vault
```

执行后应能看到：

```text
runtime-workspace/memory/projects/demo/routing/stage-route-decision.jsonl
```

如果这个文件不存在，说明宿主只生成了文档，没有部署 Product Crew OS 的路由和运行时链路。

真实 embedding 路由示例：

```bash
PCO_STAGE_ROUTER_EMBEDDING=real \
PCO_REQUIRE_REAL_EMBEDDING=1 \
ruby product-crew-os-skill/runtime/pco_runtime.rb record-turn \
  --workspace ./runtime-workspace \
  --db ./runtime-workspace/product-crew-os.sqlite3 \
  --project-id demo \
  --stage-id mvp_scope \
  --user-input "我来定：第一阶段就做审核工作台 AI 辅助判定 + 知识库 RAG 联动。" \
  --primary-skill scope-cutting \
  --fallback-skill shape-up \
  --artifact-name "mvp-scope.md" \
  --artifact-content "MVP scope draft"
```

## 5. 生成持久 Demo Vault

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
      04_需求分析/                 # 仅本次实际写入的阶段
      _项目账本/
      _团队记忆/
```

## 6. 验证

```bash
ruby product-crew-os-skill/tests/run-runtime-smoke.rb
ruby product-crew-os-skill/tests/run-sop-e2e-smoke.rb
```

通过标准：

- SQLite 数据库被创建。
- `projects`、`artifacts`、`decisions`、`review_sessions`、`raw_review_records`、`review_items`、`agent_memories`、`context_packets` 至少各有一条记录。
- Project Workspace 中存在 artifact、decision log、review items、agent memory 和 context packet。
- Project Workspace 中存在 `routing/stage-route-decision.jsonl`。
- Obsidian Vault 中存在 `00_项目首页.md`、`_项目账本/`、`_项目账本/review-sessions`、`_项目账本/raw-review-records` 和 `_团队记忆/`。
- 44 个 SOP prompt case 都能通过 `record-turn` 写入 route trace、`sop_runs`、`skill_runs`、artifact 和状态记录；模拟 smoke 不得产生通过类 Gate。真实 Skill、真实评审和最终 Gate 另有独立 E2E 证据。
- 事件表中存在 `stage_detected`、`skill_selected`、`memory_snapshot_built`、`agent_summoned`、`stage_gate_decision`。

## 7. 事实源边界

当前 Runtime 的事实源顺序是：

```text
SQLite + Project Workspace files
-> FTS index
-> Obsidian-compatible export
```

Obsidian 是可视化和检索入口，不是唯一事实源。外部修改未来必须通过 diff review 和 memory delta 写回。
