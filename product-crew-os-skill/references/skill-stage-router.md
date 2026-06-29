# Skill Stage Router

Use this file to choose a backstage skill by canonical PM stage. Prefer one primary skill and one fallback.

Only use this router after the domain intent gate confirms `product_work` or `product_crew_os_operation`. If no SOP matched because the user's request is not product-related, do not call product skills. If the request is product-related but the stage is unclear, route through `request_triage` or ask one clarifying question before choosing primary/fallback skills.

This is a coverage map, not a closed list. Product Crew OS should first resolve these skill names through `bundled-skill-index.md`, where bundled third-party implementations are mapped to `third_party/skills/`. Product Crew OS should still be able to run a full PM workflow through stage logic and artifact templates when a particular skill is missing. User-provided skills may override defaults through user/project overlays.

| Stage | Primary Skill | Fallback | Expected Output |
| --- | --- | --- | --- |
| project_intake | pm-workbench | product-manager-interrogation | project card |
| request_triage | pm-workbench | product-manager-interrogation | triage note |
| stakeholder_map | stakeholder-alignment-checker | pm-workbench | stakeholder authority map |
| business_context | product-strategy | pm-workbench / strategy-doc | business context brief |
| existing_workflow_mapping | user-story-mapping | pm-workbench | current-state workflow map |
| evidence_inventory | pm-workbench | research-synthesis | evidence inventory |
| problem_definition | problem-statement | define-problem-statement | problem statement |
| user_segmentation | jtbd-analysis | define-jtbd-canvas | segment/JTBD note |
| persona_jtbd_journey | jtbd-analysis | jobs-to-be-done / define-jtbd-canvas | persona, JTBD, or journey map |
| research_plan | product-discovery | pm-workbench | research plan |
| interview_guide | product-discovery | summarize-interview | interview guide |
| interview_synthesis | research-synthesis | user-research-synthesis | synthesis notes |
| opportunity_tree | opportunity-solution-tree | define-opportunity-tree | opportunity tree |
| assumption_mapping | assumption-mapper | problem-clarity | assumption map |
| value_sizing | feature-investment-advisor | value-vs-effort | value sizing |
| prioritization | prioritization-advisor | define-prioritization-framework | priority stack |
| solution_exploration | pm-workbench | opportunity-solution-tree / value-vs-effort | solution options brief |
| mvp_scope | scope-cutting | shape-up | MVP scope |
| one_page_proposal | pm-workbench | strategy-doc | proposal one-pager |
| data_feasibility_precheck | product-analytics | measure-dashboard-requirements | data contract |
| technical_feasibility_precheck | prd-critic | bmad-business-analyst | feasibility note |
| compliance_precheck | pm-workbench | stakeholder-alignment-checker | compliance risk note |
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
| development_tracking | pm-workbench | stakeholder-alignment-checker | change log and decision note |
| integration_qa | test-scenarios | deliver-acceptance-criteria | QA report and release risk |
| launch_readiness | deliver-launch-checklist | test-scenarios | launch checklist |
| training_enablement | pm-workbench | stakeholder-alignment-checker | enablement SOP and FAQ |
| grey_release_pilot | experiment-design | trustworthy-experiments | pilot plan |
| launch_monitoring | product-analytics | metric-dashboard | monitoring notes and incident/adoption log |
| post_launch_review | pm-workbench | roadmap-planning | postmortem |
| iteration_planning | roadmap-planning | prioritization-advisor | iteration backlog and roadmap update |

If the primary skill is unavailable, use the fallback. If both are unavailable, use the artifact template and state the missing capability plainly.

Monthly or user-triggered skill discovery may update recommended mappings, but it must not automatically install or enable new skills without user confirmation.
