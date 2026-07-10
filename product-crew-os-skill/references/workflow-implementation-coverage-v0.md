# Workflow Implementation Coverage v0 / 工作流实现覆盖矩阵

更新时间：2026-07-10

## 1. 结论

当前 Product Crew OS 不能宣称“全流程状态机和 workflow 编排都已完成”。

更准确的状态是：

> 当前主线门禁回到 44 SOP 命中、Skill Router 命中、runtime smoke 写入和 Review Ledger 可追踪；宏流程 Golden Case / 10 大主流程编排仅作为实验审计记录保留。

10 大主流程完整编排不再作为当前 release gate。若后续需要，可单独恢复为实验审计工具。

## 2. 覆盖层级

| 层级 | 当前状态 | 说明 |
| --- | --- | --- |
| SOP 卡片 | 44/44 | 每个阶段都有输入、动作、产物、干系人、过关标准 |
| Skill Router | 44/44 | 每个阶段都有 primary / fallback 映射 |
| Prompt Eval | 44/44 | 每个阶段有最小路由测试 case |
| Runtime Smoke | 44/44 | `record-turn` 可写 SQLite、artifact、review ledger、Obsidian 导出 |
| 完整状态机 Golden Case | 实验记录 | 不作为当前主线 release gate |
| 10 大主流程完整编排 | 非主线 | 当前不继续按 10 大主流程编排推进 |

注意：`Runtime Smoke` 只能证明“可写入、可追踪、可导出”，不等于“业务工作流完整可用”。

## 3. 主流程覆盖

| 主流程 | SOP/Router | Runtime Smoke | 完整状态机 | Golden Case | 主要缺口 |
| --- | --- | --- | --- | --- | --- |
| 机会发现 | implemented | tested | complete | complete | 已补齐 6 个子阶段、artifact 链、primary skill、角色触发、Gate 与负向路径 |
| 用户研究 | implemented | tested | partial | partial | research_plan 作为 selected SOP；缺完整调研流程 |
| 问题定义 | implemented | tested | missing | missing | 缺问题定义主流程状态机和 Gate 证据 |
| 需求分析 | implemented | tested | partial | missing | mvp_scope 在项目中用过，但无 Golden Case |
| 方案设计 | implemented | tested | partial | missing | 低保真和可行性只有局部测试，缺完整方案设计编排 |
| PRD 起草 | implemented | tested | missing | missing | 缺 PRD outline -> v0 -> self-review 的完整链路 |
| 跨职能评审 | implemented | tested | partial | missing | 有 structured review loop，但缺正式需求评审 Golden Case |
| 交付规划 | implemented | tested | missing | missing | 缺任务拆解到验收的完整状态机 |
| 上线准备 | implemented | tested | missing | missing | 缺 QA、上线、培训、灰度的完整上线门禁 |
| 复盘迭代 | implemented | tested | missing | missing | 缺监控、复盘、迭代规划闭环 |

## 4. 已有 Golden Case 边界

已有：

- `tests/golden-cases/flow-01-opportunity-discovery-pass.yaml`
- `tests/golden-cases/flow-01-opportunity-discovery-full.yaml`

`flow-01-opportunity-discovery-pass.yaml` 覆盖：

- 主流程：`flow_01_opportunity_discovery`
- 主覆盖阶段：`business_context`
- selected SOP：`business_context`、`evidence_inventory`、`research_plan`

`flow-01-opportunity-discovery-full.yaml` 覆盖：

- 主流程：`flow_01_opportunity_discovery`
- 主覆盖阶段：机会发现完整主流程
- selected SOP：`project_intake`、`request_triage`、`stakeholder_map`、`business_context`、`existing_workflow_mapping`、`evidence_inventory`
- 断言：状态机、artifact 链、primary skill 非 template degraded、完整 persona context packet、invocation ledger、Gate、负向路径。

不能证明：

- 用户研究主流程完整通过。
- PRD、交付、上线、复盘流程完整通过。
- 44 个 SOP 都有完整状态机和 Golden Case。

## 5. 44 个 SOP 细项状态

机器可读细项见：

- `workflow-implementation-coverage-v0.yaml`

原则：

- `sop_card: true` 表示 SOP 卡片存在。
- `runtime_smoke: true` 表示 runtime adapter 可写入测试账本。
- `has_golden_case: true` 才表示有完整 Golden Case 主覆盖。
- `state_machine_coverage: missing` 表示该阶段尚无完整状态机样例。

## 6. 下一步构建顺序

建议不要一次补完 44 个 Golden Case，而是按主流程补：

1. `flow_02_user_research`
   - `user_segmentation`
   - `research_plan`
   - `interview_guide`
   - `interview_synthesis`
   - `persona_jtbd_journey`

2. `flow_03_problem_framing`
   - `problem_definition`
   - `opportunity_tree`
   - `assumption_mapping`

3. `flow_04_requirement_analysis`
   - `value_sizing`
   - `prioritization`
   - `mvp_scope`
   - `one_page_proposal`

4. `flow_05_solution_design`
   - `solution_exploration`
   - `data_feasibility_precheck`
   - `technical_feasibility_precheck`
   - `compliance_precheck`
   - `core_flow_diagram`
   - `low_fi_prototype`
   - `metrics_design`
   - `instrumentation_plan`

5. `flow_06_prd_drafting`
   - `prd_outline`
   - `prd_v0_draft`
   - `pm_self_review`

6. `flow_07_cross_functional_review`
   - `internal_product_review`
   - `design_review`
   - `data_review`
   - `technical_pre_review`
   - `formal_requirements_review`

7. `flow_08_delivery_planning`
   - `task_breakdown`
   - `acceptance_criteria`
   - `development_tracking`

8. `flow_09_launch_readiness`
   - `integration_qa`
   - `launch_readiness`
   - `training_enablement`
   - `grey_release_pilot`

9. `flow_10_post_launch_review`
   - `launch_monitoring`
   - `post_launch_review`
   - `iteration_planning`

## 7. 发布表述

允许说：

> 当前版本已完成 SOP / Router / Runtime Smoke / 子 Agent 评审契约的基础闭环；当前主线按 44 个 SOP 命中与执行推进。

不允许说：

> 当前版本已完整跑通 PM 全流程状态机。
