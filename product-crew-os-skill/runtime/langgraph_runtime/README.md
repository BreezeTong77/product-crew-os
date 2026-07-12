# LangGraph Runtime

这是 Product Crew OS 的唯一运行时主链。它把关键控制点固化为一个持久化 LangGraph：

```text
Input Scope Gate
-> Retrieval Evidence Guard
-> Stage / SOP Route
-> Skill Execution Guard
-> Artifact Writer
-> Review Packet Builder
-> External Review Interrupt
-> Review Summary
-> User Decision Interrupt
-> Revision / Re-review
-> Project Memory / Asset Export
```

## 为什么这样拆

- Stage、SOP、Skill、Artifact、Review 和 Gate 都是图节点，不再由主控文本随意跳过。
- 外部评审和用户决策用 `interrupt()` 暂停；恢复时必须使用同一个 `thread_id` 和 `Command(resume=...)`。
- LangGraph checkpoint 与项目事实账本分开：checkpoint 用于恢复执行，项目 SQLite / Markdown 用于审计、导出和长期资产。
- Skill、RAG、MCP 和子 Agent 都是受控 adapter。没有执行证据、完整 Context Packet、真实 runtime ID、raw review 或用户确认，就不能通过 Gate。
- 外部 delegate callback 还必须带 `PCO_LANGGRAPH_DELEGATE_SECRET` 签名；只传 `runtime_agent_id` 不能证明是真实调用。
- Embedding adapter 必须返回 `provider`、`model` 和 `source_refs`。只带“相似度”或 hash 结果不会被记为真实 embedding。

## 安装

```bash
python3 -m venv .venv
.venv/bin/pip install -r product-crew-os-skill/runtime/requirements-langgraph.txt
```

## 最小运行

```bash
python3 product-crew-os-skill/runtime/pco_runtime.py init-project \
  --workspace ./runtime-workspace \
  --project-id demo \
  --name "Demo"

python3 product-crew-os-skill/runtime/pco_runtime.py record-turn \
  --workspace ./runtime-workspace \
  --project-id demo \
  --thread-id demo-run-001 \
  --user-input "我想做一个产品，第一步应该先做什么？"
```

第一次运行会在需要真实评审或用户确认处返回 `__interrupt__`。不要把这个状态写成通过；宿主必须把 interrupt payload 展示给用户或真实 delegate，之后再调用 `resume`。

## Runtime 边界

Python adapter 负责 BGE、OCR、RAG、Skill 与 Coze HTTP 接入；它们只能返回证据或执行结果。Stage、Gate、用户决策、修订和复评只能由 LangGraph 节点推进。
