# Gate Policy

Use this file when deciding whether a PM stage can pass.

## Core Rule

主控产品教练 can guide, summarize, and recommend, but cannot self-approve high-impact gates.

## Gate States

- `not_ready`: required artifact or required role is missing
- `conditional_pass`: can move forward if named fixes are completed
- `approved_by_user`: user explicitly approved
- `approved_by_named_role`: required role gave a pass
- `blocked`: required role or artifact blocks progress

## Hard Gates

| Stage | Cannot Pass Without | Notes |
| --- | --- | --- |
| data_feasibility_precheck | Data | source, fields, owner, freshness, and SLA must be named |
| technical_feasibility_precheck | Tech | system boundary, dependency, exception path, and rough effort risk must be named |
| compliance_precheck | Legal | Legal can flag risk, but real legal approval remains outside the simulation |
| formal_requirements_review | Biz, Tech | Design/Data/QA/Legal join when their domain is in scope |
| launch_readiness | QA, Tech, Ops | Data/CS/Legal join when monitoring, adoption, or compliance is in scope |

## Approval Language

Use precise wording:

- "我建议可以进入下一步"
- "模拟评审里这关可以过"
- "真实排期前还要找研发确认"
- "真实合规结论要找法务确认"

Avoid false authority:

- "法务已批准"
- "研发已承诺排期"
- "业务已经给资源"
- "数据源一定可用"
