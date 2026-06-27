# Stage Taxonomy

Use this file to map user language, macro workflow stages, and canonical fine-grained stages.

## Macro Stages

| Macro Stage | Fine Stages |
| --- | --- |
| opportunity_discovery | project_intake, request_triage, stakeholder_map, business_context, existing_workflow_mapping, evidence_inventory |
| user_research | research_plan, interview_guide, interview_synthesis, persona_jtbd_journey |
| problem_framing | problem_definition, user_segmentation, opportunity_tree, assumption_mapping |
| requirement_analysis | value_sizing, prioritization, mvp_scope, one_page_proposal |
| solution_design | solution_exploration, data_feasibility_precheck, technical_feasibility_precheck, compliance_precheck, core_flow_diagram, low_fi_prototype, metrics_design, instrumentation_plan |
| prd_drafting | prd_outline, prd_v0_draft, pm_self_review |
| cross_functional_review | internal_product_review, design_review, data_review, technical_pre_review, formal_requirements_review |
| delivery_planning | task_breakdown, acceptance_criteria, development_tracking |
| launch_readiness | integration_qa, launch_readiness, training_enablement, grey_release_pilot |
| post_launch_review | launch_monitoring, post_launch_review, iteration_planning |

## Alias Rules

- "我有个想法" -> project_intake
- "痛点对不对" -> problem_definition
- "我要找谁对齐" -> stakeholder_map
- "业务方通过了" -> one_page_proposal or formal_requirements_review depending on artifact maturity
- "找研发看看" -> technical_pre_review
- "数据可行吗" -> data_feasibility_precheck
- "写 PRD" -> prd_outline or prd_v0_draft
- "我写完 PRD 了先帮我看" -> pm_self_review
- "正式评审" -> formal_requirements_review
- "准备上线" -> launch_readiness
- "上线后看效果" -> launch_monitoring

## Transition Rule

The coach may move forward one fine stage at a time without extra confirmation. Larger jumps require a reason and user confirmation.

Common rollback paths:

- formal_requirements_review -> pm_self_review when PRD contradiction is found
- technical_pre_review -> mvp_scope when scope is too large
- data_review -> data_feasibility_precheck when field/source/SLA is missing
- launch_readiness -> acceptance_criteria when release pass/fail is unclear
- post_launch_review -> problem_definition when results disprove the original problem
