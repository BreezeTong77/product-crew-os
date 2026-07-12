# Product Crew OS Python Runtime

Product Crew OS 的唯一运行时是 Python + LangGraph。Ruby Runtime、Ruby Bridge 和 Ruby 测试不再属于发布包。

## 主流程

```text
硬规则非产品快速退出
-> 图内 BGE 检索 44 SOP
-> 输入范围判断
-> 读取项目上下文
-> Stage / SOP / Skill 路由
-> 图内 Skill 执行
-> 运行时签发并校验回执
-> Artifact
-> 完整 Context Packet
-> 真实评审回调暂停
-> 评审收束
-> 用户决策暂停
-> 修订 / 定向复评（如需要）
-> Gate
-> 项目记忆与 Obsidian 资产导出
```

`thread_id` 绑定同一条可恢复流程。`interrupt()` 不是成功：真实 delegate callback、Skill 回执和用户确认都必须在恢复时接受校验。

`record-turn` 只接受 `skill_input`，不接受调用方声称的 `skill_execution` 或 `retrieval_evidence` 成功结果。Skill 回执和路由检索证据都只由 LangGraph 节点写入。

## 安装

```bash
python3 -m venv .venv
.venv/bin/pip install -r product-crew-os-skill/runtime/requirements-langgraph.txt
```

## 本地命令

```bash
.venv/bin/python product-crew-os-skill/runtime/pco_runtime.py init-project \
  --workspace ./runtime-workspace \
  --project-id demo \
  --name "Demo"

.venv/bin/python product-crew-os-skill/runtime/pco_runtime.py rag-bootstrap \
  --workspace ./runtime-workspace

.venv/bin/python product-crew-os-skill/runtime/pco_runtime.py capability-handshake \
  --workspace ./runtime-workspace

.venv/bin/python product-crew-os-skill/runtime/pco_runtime.py route-intent \
  --workspace ./runtime-workspace \
  --project-id demo \
  --user-input "先做 MVP，不要做大，帮我砍范围。"

.venv/bin/python product-crew-os-skill/runtime/pco_runtime.py operational-metrics \
  --workspace ./runtime-workspace \
  --project-id demo
```

可用命令：`health`、`capability-handshake`、`operational-metrics`、`record-route-feedback`、`list-bad-cases`、`init-project`、`route-intent`、`execute-skill`、`rag-ingest`、`rag-bootstrap`、`rag-retrieve`、`source-extract`、`record-turn`、`resume`、`draw-graph`、`export-obsidian`。

## 运营指标与纠错

每个项目可调用 `operational-metrics`，会在项目包内写入 `运营指标/运营指标.md` 和 JSON 原始数据。它只统计 Runtime 事实：

- **SOP 确认命中率**：只用用户明确确认或纠正过的路由；没确认的不会被悄悄算作正确。
- **Skill 真执行率**：只有图内真实执行、且有 Runtime 签名回执的 Skill 才算成功；模板或调用方自报成功不算。
- **子 Agent 有效回调率**：只有真实、角色绑定且签名通过的回调才算完成。

用户可以用 `record-route-feedback` 标注一次路由是 `confirmed` 还是 `corrected`。纠正会自动产生 Bad Case；同一种错误达到配置阈值后，系统只生成待人工确认的调参建议，绝不自动改路由权重。

## Adapter 边界

- `langgraph_runtime/adapters.py`：本地 BGE、OCR、SQLite RAG、受控 Skill 执行器。
- 标准 SOP 前先执行 `rag-bootstrap`：它用本地 BGE 把 44 条 SOP 样本写入 SQLite RAG；模型或向量维度变化时会自动重建索引，避免新旧向量混算。
- 49 份内置 Skill 都由执行器发现；带脚本的能力直接运行脚本，其余方法论 Skill 会读取真实 `SKILL.md` 并通过本机 Ollama 执行。模型不可用时返回 `deployment_required`，不会退化成“Skill 已成功”。
- `pco_coze_bridge.py`：受 token 保护的 Coze HTTP Bridge，只能进入 LangGraph 的 `run` 或 `resume`，拒绝旁路写入。
- 外部 Skill 和 MCP 可以保留专业方法，但不能改 Stage、决定 Gate、写项目记忆或召唤角色。
- 真实子 Agent callback 必须包含完整 persona packet、raw review、runtime ID 和 HMAC delegate proof；`runtime_nickname` 只作审计字段。

## 本地模型与 MCP

默认模型是本机 Ollama 的 `qwen2.5:3b`。启动 Ollama 并拉取模型后，方法论 Skill 才会真实执行：

```bash
ollama serve
ollama pull qwen2.5:3b
PCO_SKILL_MODEL=qwen2.5:3b .venv/bin/python product-crew-os-skill/runtime/pco_runtime.py record-turn \
  --workspace ./runtime-workspace \
  --project-id demo \
  --user-input "先做 MVP，不要做大，帮我砍范围。"
```

Figma、Pencil 等 MCP Skill 不会被模型替代。它们需要已连接的 MCP/CLI 和用户对目标工作区的写入授权；未部署或未授权时该 SOP 会被阻塞，而不是伪造原型文件。

调用 `/v1/handshake` 会明确返回 BGE 索引、Ollama、Pencil、Figma、Coze 子 Bot 绑定和 Delegate Signer 状态。只有 44 SOP BGE 索引已建好、Ollama 模型可用、绑定完整且 Signer 可达时才可能显示 `ready_for_standard_sop`；每一次真实评审仍必须带回命中角色允许名单的 `runtime_agent_id`、`coze_invocation_id`、原文评审和 HMAC 证明。

## 测试

```bash
.venv/bin/python product-crew-os-skill/tests/validate-package.py
.venv/bin/python product-crew-os-skill/tests/run-langgraph-runtime-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-python-runtime-adapters-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-delegate-signer-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-release-gate.py
```

本机有运行中的 Ollama 时，额外执行真实模型集成测试：

```bash
.venv/bin/python product-crew-os-skill/tests/run-real-ollama-skill-integration.py
.venv/bin/python product-crew-os-skill/tests/run-real-bge-rag-integration.py
.venv/bin/python product-crew-os-skill/tests/run-standard-sop-readiness-integration.py
.venv/bin/python product-crew-os-skill/tests/run-operational-metrics-e2e.py
```

50 条发布门禁的 44 条是 Stage/SOP/Skill 路由与控制回归，不能被描述为 44 个真实 Skill 或真实外部 Agent 已全部执行。
