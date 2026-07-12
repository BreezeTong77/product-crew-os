# 44 SOP 覆盖缺口与可交付清单

更新时间：`2026-07-10`

说明：用于 Release 前快速核验每张 SOP 是否有“意图路由 → skill 路由 → runtime smoke 写入 → artifact 与评审写入 -> 回归覆盖”。

重要边界：本文件不是完整 workflow 状态机覆盖证明。44/44 runtime smoke 只能证明 `record-turn`、SQLite、Artifact、Review Ledger 和导出链路可写入，不代表 44 个 SOP 都已具备完整 Golden Case、完整 Stage Gate 编排或完整业务工作流状态机。

完整实现边界请以 `workflow-implementation-coverage-v0.md` / `workflow-implementation-coverage-v0.yaml` 为准。

## 快照

- SOP 总数：44
- Stage 路由：44/44 覆盖（`prompt-eval-cases.yaml`）
- Skill 映射：44/44 覆盖（`skill-dependency-registry.md`）
- LangGraph 路由 / Release Gate：44/44 命中（`run-langgraph-runtime-e2e.py` / `run-release-gate.py`）
- 完整状态机 / 主流程 Golden Case：实验审计记录保留，不作为当前主线门禁
- 当前主线门禁：44 SOP 命中、Skill Router 命中、Runtime Smoke 写入、Review Ledger 可追踪
- 还可优化的项：3
  - `25`：`measure-instrumentation-spec` fallback 兜底未内置主 skill
  - `30`：`develop-design-rationale` 主 skill 为建议能力，当前 fallback 运行
  - `38`：`deliver-launch-checklist` 主 skill 为建议能力，当前 fallback 运行

| # | SOP | Stage / SOP 路由 | Skill 映射 | SOP Prompt | Loop 复测 | Runtime 证据 | 缺口与行动 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | Project intake / 项目接入 | ✅ `project_intake` | ✅ `pm-workbench` / `product-manager-interrogation` | ✅ | ✅ | ✅ | 无明显缺口 |
| 1 | Request triage / 请求分流 | ✅ `request_triage` | ✅ `pm-workbench` / `product-manager-interrogation` | ✅ | ✅ | ✅ | 无明显缺口 |
| 2 | Stakeholder map / 干系人地图 | ✅ `stakeholder_map` | ✅ `stakeholder-alignment-checker` / `pm-workbench` | ✅ | ✅ | ✅ | 无明显缺口 |
| 3 | Business context / 商业背景 | ✅ `business_context` | ✅ `product-strategy` / `pm-workbench` / `strategy-doc` | ✅ | ✅ | ✅ | 无明显缺口 |
| 4 | Existing workflow mapping / 现状流程梳理 | ✅ `existing_workflow_mapping` | ✅ `user-story-mapping` / `pm-workbench` | ✅ | ✅ | ✅ | 无明显缺口 |
| 5 | Evidence inventory / 证据盘点 | ✅ `evidence_inventory` | ✅ `pm-workbench` / `research-synthesis` | ✅ | ✅ | ✅ | 无明显缺口 |
| 6 | Problem definition / 问题定义 | ✅ `problem_definition` | ✅ `problem-statement` / `define-problem-statement` | ✅ | ✅ | ✅ | 无明显缺口 |
| 7 | User segmentation / 用户分层 | ✅ `user_segmentation` | ✅ `jtbd-analysis` / `define-jtbd-canvas` | ✅ | ✅ | ✅ | 无明显缺口 |
| 8 | Research plan / 调研计划 | ✅ `research_plan` | ✅ `product-discovery` / `pm-workbench` | ✅ | ✅ | ✅ | 无明显缺口 |
| 9 | Interview guide / 访谈提纲 | ✅ `interview_guide` | ✅ `product-discovery` / `summarize-interview` | ✅ | ✅ | ✅ | 无明显缺口 |
| 10 | Interview synthesis / 访谈综合 | ✅ `interview_synthesis` | ✅ `research-synthesis` / `user-research-synthesis` | ✅ | ✅ | ✅ | 无明显缺口 |
| 11 | Persona / JTBD / Journey / 用户动机与旅程 | ✅ `persona_jtbd_journey` | ✅ `jtbd-analysis` / `jobs-to-be-done` / `define-jtbd-canvas` | ✅ | ✅ | ✅ | 无明显缺口 |
| 12 | Opportunity tree / 机会树 | ✅ `opportunity_tree` | ✅ `opportunity-solution-tree` / `define-opportunity-tree` | ✅ | ✅ | ✅ | 无明显缺口 |
| 13 | Assumption mapping / 假设地图 | ✅ `assumption_mapping` | ✅ `assumption-mapper` / `problem-clarity` | ✅ | ✅ | ✅ | 无明显缺口 |
| 14 | Value sizing / 价值测算 | ✅ `value_sizing` | ✅ `feature-investment-advisor` / `value-vs-effort` | ✅ | ✅ | ✅ | 无明显缺口 |
| 15 | Prioritization / 优先级排序 | ✅ `prioritization` | ✅ `prioritization-advisor` / `define-prioritization-framework` | ✅ | ✅ | ✅ | 无明显缺口 |
| 16 | Solution exploration / 方案探索 | ✅ `solution_exploration` | ✅ `pm-workbench` / `opportunity-solution-tree` / `value-vs-effort` | ✅ | ✅ | ✅ | 无明显缺口 |
| 17 | MVP scope / MVP 范围 | ✅ `mvp_scope` | ✅ `scope-cutting` / `shape-up` | ✅ | ✅ | ✅ | 无明显缺口 |
| 18 | One-page proposal / 一页方案 | ✅ `one_page_proposal` | ✅ `pm-workbench` / `strategy-doc` | ✅ | ✅ | ✅ | 无明显缺口 |
| 19 | Data feasibility precheck / 数据可行性预检 | ✅ `data_feasibility_precheck` | ✅ `product-analytics` / `measure-dashboard-requirements` | ✅ | ✅ | ✅ | 无明显缺口 |
| 20 | Technical feasibility precheck / 技术可行性预检 | ✅ `technical_feasibility_precheck` | ✅ `prd-critic` / `bmad-business-analyst` | ✅ | ✅ | ✅ | 无明显缺口 |
| 21 | Compliance precheck / 合规预检 | ✅ `compliance_precheck` | ✅ `pm-workbench` / `stakeholder-alignment-checker` | ✅ | ✅ | ✅ | 无明显缺口 |
| 22 | Core flow diagram / 核心流程图 | ✅ `core_flow_diagram` | ✅ `user-story-mapping` / `figma:figma-generate-diagram` | ✅ | ✅ | ✅ | 无明显缺口 |
| 23 | Low-fi prototype / 低保真原型 | ✅ `low_fi_prototype` | ✅ `pencil-design` / `figma:figma-use` | ✅ | ✅ | ✅ | 无明显缺口 |
| 24 | Metrics design / 指标设计 | ✅ `metrics_design` | ✅ `metrics-framework` / `north-star-metric` | ✅ | ✅ | ✅ | 无明显缺口 |
| 25 | Instrumentation plan / 埋点计划 | ✅ `instrumentation_plan` | ✅ `measure-instrumentation-spec` / `product-analytics` | ✅ | ✅ | ✅ | ⚠️ 主 skill `measure-instrumentation-spec` 当前未内置；以 fallback + `tracking plan` 模板兜底，建议补 wrapper 或插件化实现。 |
| 26 | PRD outline / PRD 大纲 | ✅ `prd_outline` | ✅ `prd-development` / `prd-writing` | ✅ | ✅ | ✅ | 无明显缺口 |
| 27 | PRD v0 draft / PRD 初稿 | ✅ `prd_v0_draft` | ✅ `deliver-prd` / `prd-taskmaster` | ✅ | ✅ | ✅ | 无明显缺口 |
| 28 | PM self-review / 产品自审 | ✅ `pm_self_review` | ✅ `prd-critic` / `product-manager-skills` | ✅ | ✅ | ✅ | 无明显缺口 |
| 29 | Internal product review / 内部产品评审 | ✅ `internal_product_review` | ✅ `utility-pm-critic` / `stakeholder-alignment-checker` | ✅ | ✅ | ✅ | 无明显缺口 |
| 30 | Design review / 设计评审 | ✅ `design_review` | ✅ `develop-design-rationale` / `user-story-mapping` | ✅ | ✅ | ✅ | ⚠️ `develop-design-rationale` 当前为建议能力；当前走 `user-story-mapping` fallback，建议补可验证的设计评审能力。 |
| 31 | Data review / 数据评审 | ✅ `data_review` | ✅ `product-analytics` / `metric-dashboard` | ✅ | ✅ | ✅ | 无明显缺口 |
| 32 | Technical pre-review / 技术预评审 | ✅ `technical_pre_review` | ✅ `prd-critic` / `code-to-prd` | ✅ | ✅ | ✅ | 无明显缺口 |
| 33 | Formal requirements review / 正式需求评审 | ✅ `formal_requirements_review` | ✅ `stakeholder-alignment-checker` / `pm-workbench` | ✅ | ✅ | ✅ | 无明显缺口 |
| 34 | Task breakdown / 任务拆解 | ✅ `task_breakdown` | ✅ `prd-taskmaster` / `deliver-user-stories` | ✅ | ✅ | ✅ | 无明显缺口 |
| 35 | Acceptance criteria / 验收标准 | ✅ `acceptance_criteria` | ✅ `deliver-acceptance-criteria` / `test-scenarios` | ✅ | ✅ | ✅ | 无明显缺口 |
| 36 | Development tracking / 开发变更跟踪 | ✅ `development_tracking` | ✅ `pm-workbench` / `stakeholder-alignment-checker` | ✅ | ✅ | ✅ | 无明显缺口 |
| 37 | Integration / QA / 联调测试 | ✅ `integration_qa` | ✅ `test-scenarios` / `deliver-acceptance-criteria` | ✅ | ✅ | ✅ | 无明显缺口 |
| 38 | Launch readiness / 上线准备 | ✅ `launch_readiness` | ✅ `deliver-launch-checklist` / `test-scenarios` | ✅ | ✅ | ✅ | ⚠️ `deliver-launch-checklist` 当前为建议能力；当前走 `test-scenarios` fallback，建议补 launch-checklist 真实实现。 |
| 39 | Training / enablement / 培训赋能 | ✅ `training_enablement` | ✅ `pm-workbench` / `stakeholder-alignment-checker` | ✅ | ✅ | ✅ | 无明显缺口 |
| 40 | Grey release / pilot / 灰度试点 | ✅ `grey_release_pilot` | ✅ `experiment-design` / `trustworthy-experiments` | ✅ | ✅ | ✅ | 无明显缺口 |
| 41 | Launch monitoring / 上线监控 | ✅ `launch_monitoring` | ✅ `product-analytics` / `metric-dashboard` | ✅ | ✅ | ✅ | 无明显缺口 |
| 42 | Post-launch review / 上线复盘 | ✅ `post_launch_review` | ✅ `pm-workbench` / `roadmap-planning` | ✅ | ✅ | ✅ | 无明显缺口 |
| 43 | Iteration planning / 迭代规划 | ✅ `iteration_planning` | ✅ `roadmap-planning` / `prioritization-advisor` | ✅ | ✅ | ✅ | 无明显缺口 |
