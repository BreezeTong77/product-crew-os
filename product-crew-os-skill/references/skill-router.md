# Skill Router

主控产品教练 should route to existing product skills as backstage capabilities. Do not present a long menu unless the user asks.

This file is a default registry, not a hard limit. Users may bring their own skills, templates, scripts, or internal standards. If a user-provided skill fits the current stage better than the default, prefer the user skill after confirming its input, output, stage, and safety boundary.

Before using this router, first confirm the request belongs to product work or Product Crew OS operation. If it is a non-product task, skip this router and answer normally or use a relevant non-product capability. If it is product-related but ambiguous, use `request_triage` or a clarifying question before choosing a product skill.

| Need | Skill Family | When to Use |
| --- | --- | --- |
| Clarify fuzzy request | pm-workbench / clarify-request | user has a vague idea or mixed goals |
| Product idea interrogation | skill-product-manager | Chinese-context PM critique, sharp questioning |
| PRD creation | prd-taskmaster / prd-writing / deliver-prd | user asks to write or refine PRD |
| PRD critique | prd-critic / product-manager-skills | review clarity, testability, logic gaps |
| JTBD | jtbd-analysis / jobs-to-be-done / define-jtbd-canvas | user research or motivation analysis |
| Opportunity mapping | opportunity-solution-tree / opportunity-mapping | discover opportunity tree or solution options |
| Prioritization | feature-prioritization / prioritization-matrix / value-vs-effort | compare backlog, rank features, choose scope |
| Metrics | metrics-framework / metric-dashboard / product-analytics | define success and guardrails |
| Experiment | experiment-design / trustworthy-experiments | validate assumptions or A/B tests |
| Roadmap | roadmap-planning / outcome-roadmap | sequence initiatives and commitments |
| Release | test-scenarios / deliver-acceptance-criteria | acceptance criteria, QA, rollout readiness |

Routing rule:

1. Pass the domain intent gate.
2. Pick the upstream skill first.
3. Pick one primary skill unless the workflow clearly needs a chain.
4. After the skill output, decide whether stakeholder review is needed.
5. Convert review results into artifact edits.
6. If no installed skill fits, use the artifact template and clearly state the missing capability.
7. If the user has a preferred skill, tool, or software workflow, adapt to it instead of forcing the default stack.

## Codex Host Rule

在 Codex 中，内置于 `third_party/skills/` 的 Skill 是宿主原生能力，不需要再部署 Ollama 或第二个模型。命中后主控必须读取并实际遵循该 Skill 的 `SKILL.md`，把它的专业方法用于当前 Artifact；然后记录 `host_native_executed` 证据。只有 Figma/Pencil 等 MCP 能力、用户自带私有 Skill、或本包不存在的 fallback，才需要额外部署、授权或显式降级。
