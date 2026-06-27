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
| Hallucinated fact | invents data source or stakeholder approval | mark incident, correct answer, update source ledger |
| Context loss | forgets prior decision or open risk | restore checkpoint, reload project state and decision log |
| Wrong agent summoned | calls Legal during ordinary PRD draft | log routing error, check boundary matrix |
| Missing agent | skips Data before metric/data review | log routing error, update trigger if repeated |
| Over-agenting | full panel appears for simple draft | reduce max agents, enforce review gate |
| Tool bug | MCP action fails or changes wrong artifact | rollback from checkpoint, require dry run |
| Stale memory | old decision overrides newer decision | use decision timestamps and latest-confirmed priority |
| Jargon drift | agents become checklist machines | apply sub-agent natural-language rewrite rule |

## Lightweight Evolution Check

Run after each stage:

1. Did the coach choose the right stage?
2. Did the coach summon only allowed roles?
3. Did the user correct a fact, decision, or tone?
4. Did we create or revise an artifact?
5. Did any memory need to be written, updated, or forgotten?
6. Is the next action still clear?

Output: `memory/projects/{project_id}/evolution-notes.md`

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
