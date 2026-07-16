# Evolution Loop

Use this file to prevent Product Crew OS from becoming stale, hallucinating, losing context, or silently accumulating workflow bugs.

## What Evolution Means

Evolution is not more agent chat. It is the maintenance loop around the product coach:

1. Observe what happened.
2. Detect failure patterns.
3. Compress useful memory without losing decisions.
4. Update rules or config only when justified.
5. Run regression scenarios.
6. Ask the user before durable behavior changes.

## Failure Classes

| Failure | Example | Response |
| --- | --- | --- |
| Wrong stage routed | treats a prototype request as a generic UI task | log routing feedback, correct stage, check semantic stage router |
| Hallucinated fact | invents data source or stakeholder approval | mark incident, correct answer, update source ledger |
| Context loss | forgets prior decision or open risk | restore checkpoint, reload project state and decision log |
| Wrong agent summoned | calls Legal during ordinary PRD draft | log routing error, check boundary matrix |
| Missing agent | skips Data before metric/data review | log routing error, update trigger if repeated |
| Over-agenting | full panel appears for simple draft | reduce max agents, enforce review gate |
| Tool bug | MCP action fails or changes wrong artifact | rollback from checkpoint, require dry run |
| Stale memory | old decision overrides newer decision | use decision timestamps and latest-confirmed priority |
| Jargon drift | agents become checklist machines | apply sub-agent natural-language rewrite rule |

## Confirmed Product Rule Bad Cases

### BC-INTAKE-001: 一句话想法被越级扩写

- **触发**：用户只说“我想做一个爆款人格测试，类似某热点测试”。
- **错误表现**：虽然命中了 `project_intake`，但系统把宏观阶段和当前 SOP 混写；未经来源验证就写入目标用户、痛点、热点结论和需求真实性分，并把 fake door、结果库等后续方案写成已决定下一步。
- **根因**：项目接入只有路由和通用 artifact 规则，没有“事实 / 假设 / 未知”隔离，也没有把 route trace、最小输入和 Biz 触发作为项目接入的硬门槛。
- **修复**：LangGraph 增加 `project_intake_guard`；项目卡附带事实、假设、缺口和禁止提前决定项；“爆款 / 增长 / 传播”等词触发 Biz；缺 owner、目标用户或成功定义时不能通过 Gate。
- **回归**：L51 与 `run-project-intake-guard-e2e.py`。
- **长期规则**：未知保持未知。没有 `source_ref` 的市场结论、需求分数和方案承诺只能是候选，不是项目事实。

## Lightweight Evolution Check

Run after each stage:

1. Did the coach choose the right stage?
2. Did the coach summon only allowed roles?
3. Did the user correct a fact, decision, or tone?
4. Did we create or revise an artifact?
5. Did any memory need to be written, updated, or forgotten?
6. Is the next action still clear?
7. Did the user correct the current stage, SOP, skill, sub-agent, or artifact route?

Output: `memory/projects/{project_id}/evolution-notes.md`

If stage routing was corrected, also write a routing feedback item:

```json
{
  "event_type": "stage_routing_feedback",
  "user_utterance": "<original user request>",
  "wrong_stage": "<stage originally chosen>",
  "correct_stage": "<stage after correction>",
  "expected_sop": "<SOP card>",
  "missed_skill": "<primary/fallback skill if any>",
  "missed_roles": ["<role_key>"],
  "missed_artifact": "<artifact>",
  "lesson": "<short reusable lesson>"
}
```

## Weekly Evolution Review

Run weekly for active projects:

1. Review event log.
2. Count routing errors.
3. Count guardrail failures.
4. Review unresolved risks older than 7 days.
5. Review user corrections.
6. Check whether project memory contradicts the latest decision log.
7. Propose small config/rule changes.

Do not apply durable changes automatically. Ask:

> 我发现这周有几个重复问题，要不要我把它们写进团队记忆/边界规则里？

## Incident Review

Run after three guardrail failures or one high-impact hallucination:

1. Stop automation for the current action.
2. State what went wrong in plain language.
3. Identify source: stage detection, memory recall, agent boundary, tool action, or artifact schema.
4. Restore from latest safe checkpoint if needed.
5. Ask whether to adjust rules.

## Memory Hygiene

Use this rule:

> The latest explicit user decision beats older summaries. Artifact facts beat remembered impressions. Unknown stays unknown.

Memory update types:

- append new decision
- supersede old decision
- mark assumption as validated
- mark assumption as rejected
- forget stale preference
- compress long discussion

## Human Approval Required

Ask before:

- changing global user preferences
- changing role persona
- changing stakeholder boundary
- marking a stage approved
- sending external communication
- writing to Jira/Figma/Canva/Draw.io or similar external tools
- deleting or overwriting artifacts

## Semantic Routing Evolution

Stage routing should improve over time, but it must respect memory boundaries.

Allowed evolution sources:

- User corrections about stage, SOP, skill, role, or artifact.
- Repeated routing mistakes found in regression scenarios.
- Project decision logs and artifact metadata.
- User-approved company SOP, templates, meeting transcripts, or team comments.

Storage rules:

- Generic routing lessons may become Product Rule Memory after review.
- User-specific phrasing and workflow preferences belong in User Preference Memory.
- Project-specific examples, documents, customers, teammates, and decisions belong only in Project Workspace Memory.

Future implementation may use embedding, vector search, or RAG to retrieve similar stage-routing cases, but retrieval must never override stage gates or memory-container isolation.
