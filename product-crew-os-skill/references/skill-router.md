# Skill Router

主控产品教练 should route to existing product skills as backstage capabilities. Do not present a long menu unless the user asks.

This file is a default registry, not a hard limit. Users may bring their own skills, templates, scripts, or internal standards. If a user-provided skill fits the current stage better than the default, prefer the user skill after confirming its input, output, stage, and safety boundary.

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

1. Pick the upstream skill first.
2. Pick one primary skill unless the workflow clearly needs a chain.
3. After the skill output, decide whether stakeholder review is needed.
4. Convert review results into artifact edits.
5. If no installed skill fits, use the artifact template and clearly state the missing capability.
6. If the user has a preferred skill, tool, or software workflow, adapt to it instead of forcing the default stack.
