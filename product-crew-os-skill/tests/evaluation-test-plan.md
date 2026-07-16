# Product Crew OS Python / LangGraph 测试计划

当前发布包不使用 Ruby。所有当前测试都通过 Python 运行，并把 LangGraph 作为唯一流程控制器。

| 层级 | 目标 | 命令 |
| --- | --- | --- |
| L0 | 文件、YAML/JSON、Docker 与无 Ruby Runtime 校验 | `validate-package.py` |
| L1 | 44 SOP 路由、Gate、评审、修订与 checkpoint | `run-langgraph-runtime-e2e.py` |
| L2 | BGE/OCR/RAG/Skill/Coze Python adapter | `run-python-runtime-adapters-e2e.py` |
| L3 | 44 SOP 路由控制 + L45-L51 高风险边界 | `run-release-gate.py` |

```bash
python3 -m venv .venv
.venv/bin/pip install -r product-crew-os-skill/runtime/requirements-langgraph.txt
.venv/bin/python product-crew-os-skill/tests/validate-package.py
.venv/bin/python product-crew-os-skill/tests/run-langgraph-runtime-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-python-runtime-adapters-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-project-intake-guard-e2e.py
.venv/bin/python product-crew-os-skill/tests/run-release-gate.py
```

## 发布口径

- 44 条基准用例验证的是 LangGraph 的 Stage / SOP / 主 Skill 路由与控制链，不等于 44 个专业 Skill 都被真实外部模型执行。
- 真实 embedding 只有本地 BGE provider 返回 `provider`、`model`、来源引用和向量时才可标记为真实；hash 只用于 smoke。
- 真实子 Agent 只有通过完整 persona packet、HMAC delegate proof、runtime ID 和 raw review 校验时才可进入 Gate。
- 测试夹具中的签名 callback 只验证 adapter 契约，不能表述为线上子 Agent 调用。
