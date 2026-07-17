# Host Runtime Compliance / 宿主运行时合规契约

Product Crew OS 不能只作为 Prompt 运行。任何宿主（Coze、Codex 新窗口、Dify、LangGraph、自研 Bot）在进入标准 SOP 模式前，必须先完成能力握手。

## 1. Capability Handshake

宿主启动项目或进入标准 SOP 时，必须记录：

```yaml
runtime_capabilities:
  route_trace_writer: connected | missing
  sop_router: connected | missing
  skill_router: connected | missing
  real_embedding_provider: connected | missing
  vector_index: connected | missing
  project_database: connected | missing
  artifact_writer: connected | missing
  subagent_delegate: connected | missing
  invocation_ledger: connected | missing
  raw_review_writer: connected | missing
```

最低通过线：

- `route_trace_writer=connected`
- `sop_router=connected`
- `skill_router=connected`
- `project_database=connected`
- `artifact_writer=connected`

标准 SOP 通过线额外要求：

- `real_embedding_provider=connected`
- `vector_index=connected`
- Required / Triggered roles 对应的 `subagent_delegate=connected`
- `invocation_ledger=connected`
- `raw_review_writer=connected`

## 2. 禁止冒名

以下降级不能冒名为真实能力：

| 降级 | 允许用途 | 禁止说成 |
| --- | --- | --- |
| TF-IDF / keyword / local hash | CI smoke 或临时召回 | real embedding |
| 同线程角色扮演 | advice_only 草稿意见 | real sub-agent invocation |
| 手动查表 | 解释阶段判断 | SOP Router 已部署 |
| 只写 Markdown | 草稿产物 | Project Workspace / database 已接入 |
| 主控总结角色观点 | 摘要 | raw review record |

如果宿主缺少真实能力，必须写：

```yaml
runtime_status: runtime_not_connected | runtime_degraded
invalid_for_gate: true
```

## 3. Gate 规则

标准 SOP 模式下，Stage Gate 只有在以下证据全部存在时才可 `pass` 或 `conditional_pass`：

- `routing/stage-route-decision.jsonl` 或等价 route trace 表。
- route decision 包含 `candidate_routes`、`retrieval_mode`、`confidence`、`source_refs`。
- 如果启用标准用户运行，`real_embedding_performed=true`。
- `skill_runs` 记录 selected skill，且 `skill_status != template_degraded`。
- Required roles 有真实 `agent_invocations(real_invocation_performed=true)`。
- 每个真实角色有完整 persona context packet。
- 每个评审角色的原文进入 `raw-review-records/`。

缺任一项时：

```yaml
gate_status: blocked_runtime_preflight
```

## 4. Coze 适配红线

Coze Bot 只复制 README / SKILL.md / reference 文档，不等于部署 Product Crew OS。

Coze 必须至少有：

- 主控 Bot。
- Workflow route node。
- Database / table 写入节点。
- Embedding / vector recall node，或调用外部 runtime API。
- 子 Bot 调用节点。
- Artifact writer。
- Review ledger writer。

没有这些节点时，主控只能给建议和草稿，不能说“已按 Product Crew OS 标准 SOP 跑完”。

## 5. 部署验收

本地 package 测试通过，不代表 Coze、Codex 新窗口或自研前端已经连到 Bridge。对每个实际宿主，先运行：

```bash
PCO_HOST_RUNTIME_URL="https://your-runtime.example.com" \
PCO_RUNTIME_TOKEN="<runtime-token>" \
.venv/bin/python product-crew-os-skill/tests/run-host-bridge-acceptance.py
```

只有返回 `host_bridge_acceptance: PASS`，宿主才可以声称自己已接入 LangGraph 标准 SOP。返回 `deployment_required`、`FAIL` 或 `runtime_degraded` 时，只能输出建议或草稿，并明确标记 `runtime_not_connected`。
