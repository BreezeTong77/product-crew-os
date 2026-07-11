# Coze 真实部署清单

这份清单部署的是 Product Crew OS Runtime Bridge，不是把 `SKILL.md` 粘到 Bot Prompt。

## 1. 启动受保护 Runtime

在发布包根目录执行：

```bash
cp product-crew-os-skill/integrations/coze/.env.example product-crew-os-skill/integrations/coze/.env
docker compose --env-file product-crew-os-skill/integrations/coze/.env \
  -f product-crew-os-skill/integrations/coze/docker-compose.yml up -d --build
```

首次启动会下载 `BAAI/bge-small-zh-v1.5`。不要用 `local_hash_dry_run` 作为线上环境变量。

验证：

```bash
curl -H "Authorization: Bearer $PCO_RUNTIME_TOKEN" http://127.0.0.1:8787/health
curl -X POST -H "Authorization: Bearer $PCO_RUNTIME_TOKEN" \
  http://127.0.0.1:8787/v1/handshake
```

把 Runtime 放到 Coze 可访问的 HTTPS 域名后，再继续下一步。不能把本机 `localhost` 填入 Coze 插件。

## 2. 导入 Coze API 插件

在 Coze 的 API 插件导入页导入 `runtime-plugin-openapi.yaml`：

1. 先把 `servers[0].url` 替换为 Runtime 的 HTTPS 域名。
2. 配置 Bearer Token，值为 `PCO_RUNTIME_TOKEN`。
3. 调用 `runtimeCapabilityHandshake`；只有返回 `ready_for_standard_sop` 才能进入标准 SOP。
4. 若结果是 `runtime_degraded`，先修复 `missing_capabilities`，不要继续让主控 Bot 写业务文档。

## 3. 创建 Coze Database 镜像表

按 `database-schema.yaml` 创建：

- `pco_projects`
- `pco_route_traces`
- `pco_artifacts`
- `pco_review_sessions`
- `pco_agent_invocations`
- `pco_raw_review_records`
- `pco_review_items`
- `pco_stage_gates`
- `pco_rag_ingestions`
- `pco_retrieval_events`

这些表用于在 Coze 控制台审计 Workflow。Stage Gate 的事实源仍是 Runtime SQLite + Project Workspace。

## 4. 创建并绑定子 Bot

从 `sub-bot-bindings.example.yaml` 复制一份私有 `sub-bot-bindings.private.yaml`，填入真实 Coze Bot ID。每个子 Bot 接收 Bridge 返回的完整 `context_packet`，并输出：

```json
{
  "raw_review": "完整原文评审",
  "conclusion": "pass | conditional_pass | block",
  "review_items": []
}
```

Workflow 必须把 Call Bot 节点的真实 `runtime_agent_id` 连到 `runtimeRecordSubBotCallback`。同线程 prompt 切换角色不允许接入该节点。

## 5. 按节点图连线

严格使用 `workflow-node-map.yaml`：

```text
Handshake -> Route -> Database Mirror -> Skill -> Turn Writer
-> Sub Bot Delegate -> Real Review Callback -> Review Items
-> User Decision -> Finalize Gate -> Obsidian Export
```

`runtimeRecordTurn` 有 `review_roles` 时只生成 Review Session 和 complete Context Packet。没有回调前，返回状态必须是 `awaiting_external_review`。只有 `runtimeFinalizeStageGate` 可以返回 `pass` 或 `conditional_pass`。

## 6. 线上验收样本

至少跑一条需要 `Tech` 和 `Design` 的正式评审，逐项核对：

- `route_decision_id` 和 `real_embedding_performed=true`。
- `skill_status` 不是 `template_degraded`。
- 若 Coze 实际执行了外部 Skill / Skill Workflow，`runtimeRecordTurn` 请求必须带 `skill_execution`；其中四项控制边界均为 `false`：改 Stage、决定 Gate、写项目记忆、召唤子 Bot。未带契约或出现未授权动作时，runtime 会写入草稿但阻塞 Gate。
- 每个 Required Role 有真实 `runtime_agent_id`。
- 每个 Callback 有 `context_packet_quality=complete`、raw review 和 Coze Database 镜像行。
- 用户决策写入后才调用 `runtimeFinalizeStageGate`。
- Obsidian 导出含 `_项目账本/routing`、`raw-review-records`、`review-sessions`。

任一项缺失时，结果应是 `runtime_degraded`、`awaiting_user_decision` 或 `blocked_runtime_preflight`，不能显示为阶段通过。
