# Release Gate Bad Cases

| Case | 防止的问题 | Python / LangGraph 保护 |
| --- | --- | --- |
| L45 | 普通问题被强行套 SOP | `input_scope_gate` 直接退出 |
| L46 | 宿主昵称覆盖配置角色 | `role_key` 决定身份，`runtime_nickname` 仅审计 |
| L47 | 主控摘要替代原始评审 | callback 必须写入 `raw-review-records/` |
| L48 | 未授权资料进入私有 RAG | private namespace 必须有 `consent_ref` |
| L49 | 项目资料停留在聊天 | `export_project_assets` 写项目首页和 manifest |
| L50 | 主控替用户通过 Gate | `await_user_decision` 必须收到用户确认 |

这些边界由 [run-release-gate.py](run-release-gate.py) 验证。
