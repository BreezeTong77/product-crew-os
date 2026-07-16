# Python Release Gate Ledger

`run-release-gate.py` 每次运行在临时 workspace 中创建真实 LangGraph SQLite checkpoint、项目事实账本与 Artifact 文件。它不复用旧的 Ruby SQLite ledger。

## 51 条用例结构

- `S00-S43`：44 个 SOP 基准，断言输入命中预期 Stage 与主 Skill。
- `L45`：普通问题必须退出 Product Crew OS。
- `L46`：`runtime_nickname` 只能做审计信息。
- `L47`：raw review 必须写入可查看文件。
- `L48`：私有 RAG 没有 `consent_ref` 时必须拒绝。
- `L49`：项目资产导出必须落入项目文件夹。
- `L50`：用户暂缓或未确认时不能通过 Gate。
- `L51`：一句产品想法必须命中 `project_intake`；缺少负责人、目标用户或成功定义时，保留为待澄清而不是写成市场结论或已决定方案。

运行：

```bash
.venv/bin/python product-crew-os-skill/tests/run-release-gate.py
```

每轮默认重新执行；不允许把旧 PASS、template_degraded、hash embedding 或模拟评审作为发布通过依据。
