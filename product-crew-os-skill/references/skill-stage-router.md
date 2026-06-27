# Skill Stage Router

Use this file to choose a backstage skill by canonical PM stage. Prefer one primary skill and one fallback.

This is a coverage map, not a closed list. Product Crew OS should be able to run a full PM workflow through stage logic and artifact templates even when a particular skill is missing. User-provided skills may override defaults through user/project overlays.

| Stage | Primary Skill | Fallback | Expected Output |
| --- | --- | --- | --- |
| project_intake | pm-workbench | product-manager-interrogation | project card |
| stakeholder_map | stakeholder-alignment-checker | pm-workbench | stakeholder authority map |
| evidence_inventory | pm-workbench | research-synthesis | evidence inventory |
| problem_definition | problem-statement | define-problem-statement | problem statement |
| user_segmentation | jtbd-analysis | define-jtbd-canvas | segment/JTBD note |
| research_plan | product-discovery | pm-workbench | research plan |
| interview_guide | product-discovery | summarize-interview | interview guide |
| interview_synthesis | research-synthesis | user-research-synthesis | synthesis notes |
| opportunity_tree | opportunity-solution-tree | define-opportunity-tree | opportunity tree |
| assumption_mapping | assumption-mapper | problem-clarity | assumption map |
| value_sizing | feature-investment-advisor | value-vs-effort | value sizing |
| prioritization | prioritization-advisor | define-prioritization-framework | priority stack |
| mvp_scope | scope-cutting | shape-up | MVP scope |
| one_page_proposal | pm-workbench | strategy-doc | proposal one-pager |
| data_feasibility_precheck | product-analytics | measure-dashboard-requirements | data contract |
| technical_feasibility_precheck | prd-critic | bmad-business-analyst | feasibility note |
| core_flow_diagram | user-story-mapping | figma:figma-generate-diagram | flow diagram brief |
| low_fi_prototype | pencil-design | figma:figma-use | low-fi prototype brief |
| metrics_design | metrics-framework | north-star-metric | metrics tree |
| instrumentation_plan | measure-instrumentation-spec | product-analytics | event spec |
| prd_outline | prd-development | prd-writing | PRD outline |
| prd_v0_draft | deliver-prd | prd-taskmaster | PRD v0 |
| pm_self_review | prd-critic | product-manager-skills | self-review notes |
| internal_product_review | utility-pm-critic | stakeholder-alignment-checker | review notes |
| design_review | develop-design-rationale | user-story-mapping | design review |
| data_review | product-analytics | metric-dashboard | data review |
| technical_pre_review | prd-critic | code-to-prd | tech pre-review |
| formal_requirements_review | stakeholder-alignment-checker | pm-workbench | decision log |
| task_breakdown | prd-taskmaster | deliver-user-stories | technical task breakdown |
| acceptance_criteria | deliver-acceptance-criteria | test-scenarios | acceptance criteria and test scenario library |
| launch_readiness | deliver-launch-checklist | test-scenarios | launch checklist |
| grey_release_pilot | experiment-design | trustworthy-experiments | pilot plan |
| post_launch_review | pm-workbench | roadmap-planning | postmortem |

If the primary skill is unavailable, use the fallback. If both are unavailable, use the artifact template and state the missing capability plainly.

Monthly or user-triggered skill discovery may update recommended mappings, but it must not automatically install or enable new skills without user confirmation.
