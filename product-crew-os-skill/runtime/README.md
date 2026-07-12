# Product Crew OS Python Runtime

Product Crew OS 的唯一运行时是 Python + LangGraph。Ruby Runtime、Ruby Bridge 和 Ruby 测试不再属于发布包。

## 主流程

```text
输入范围判断
-> 读取项目上下文
-> 检索证据
-> Stage / SOP / Skill 路由
-> Skill 执行门禁
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
- `pco_coze_bridge.py`：受 token 保护的 Coze HTTP Bridge，只能进入 LangGraph 的 `run` 或 `resume`，拒绝旁路写入。
- 外部 Skill 和 MCP 可以保留专业方法，但不能改 Stage、决定 Gate、写项目记忆或召唤角色。
- 真实子 Agent callback 必须包含完整 persona packet、raw review、runtime ID 和 HMAC delegate proof；`runtime_nickname` 只作审计字段。

## 测试

```bash
.venv/bin/python product-crew-os-skill/tests/validate-package.py
.venv/bin/python product-crew-os-skill/tests/run-langgraph-runtime-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-python-runtime-adapters-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-release-gate.py
```

50 条发布门禁的 44 条是 Stage/SOP/Skill 路由与控制回归，不能被描述为 44 个真实 Skill 或真实外部 Agent 已全部执行。
