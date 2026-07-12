# Product Crew OS Python Runtime

Product Crew OS 的唯一运行时是 Python + LangGraph。Ruby Runtime、Ruby Bridge 和 Ruby 测试不再属于发布包。

## 主流程

```text
输入范围判断
-> 读取项目上下文
-> 检索证据
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

`record-turn` 只接受 `skill_input`，不接受调用方声称的 `skill_execution` 成功结果。执行回执只由 LangGraph 的 `execute_skill` 节点写入。

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

.venv/bin/python product-crew-os-skill/runtime/pco_runtime.py route-intent \
  --workspace ./runtime-workspace \
  --project-id demo \
  --user-input "先做 MVP，不要做大，帮我砍范围。"
```

可用命令：`health`、`init-project`、`route-intent`、`execute-skill`、`rag-ingest`、`rag-retrieve`、`source-extract`、`record-turn`、`resume`、`draw-graph`、`export-obsidian`。

## Adapter 边界

- `langgraph_runtime/adapters.py`：本地 BGE、OCR、SQLite RAG、受控 Skill 执行器。
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

## 测试

```bash
.venv/bin/python product-crew-os-skill/tests/validate-package.py
.venv/bin/python product-crew-os-skill/tests/run-langgraph-runtime-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-python-runtime-adapters-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-release-gate.py
```

本机有运行中的 Ollama 时，额外执行真实模型集成测试：

```bash
.venv/bin/python product-crew-os-skill/tests/run-real-ollama-skill-integration.py
```

50 条发布门禁的 44 条是 Stage/SOP/Skill 路由与控制回归，不能被描述为 44 个真实 Skill 或真实外部 Agent 已全部执行。
