# Skill Dependency Registry

本文件说明 Product Crew OS 的 Skill Router 如何理解 primary skill、fallback skill、内置第三方 skill，以及这些 skill 与开源包的关系。

## 1. Primary 与 Fallback 的区别

| 类型 | 含义 | 使用时机 | 用户感知 |
| --- | --- | --- | --- |
| Primary Skill | 当前 stage 最推荐、最贴题的能力 | 该 skill 已内置或用户环境可调用，且输入符合它的适用范围 | 主控教练可以简单说明“我先用范围裁剪能力处理” |
| Fallback Skill | Primary 不可用、过重、过窄或当前输入不适合时的兜底能力 | primary 缺失、失败、输出不适合，或用户明确偏好另一路径 | 主控教练应说明“我会用备用能力/模板继续，不让流程中断” |
| Artifact Template | skill 都不可用时的规则包兜底 | primary 和 fallback 都不可用，或用户只需要轻量产物 | 主控教练直接按 SOP 和模板生成 v0，并标注缺失能力 |
| User Skill Overlay | 用户自带 skill、公司模板或团队规范 | 用户提供的能力更贴合当前工作流 | 优先使用用户能力，但仍保留输入、输出、子 Agent 和 Stage Gate |

Primary 不是“唯一正确答案”，fallback 也不是“低质量替代”。它们共同保证：

```text
domain intent gate -> stage -> primary skill -> fallback skill -> artifact template -> stage gate
```

即使某个 skill 缺失，Product Crew OS 也必须继续完成可编辑 artifact，而不是停在“缺工具”。

Skill Router 不是通用意图分发器。只有请求属于产品工作或 Product Crew OS 自身配置/维护时，才进入本注册表。非产品请求不需要 primary/fallback skill，也不需要 artifact template 或 stage gate。

## 2. 可用性分层

| 状态 | 含义 | 规则 |
| --- | --- | --- |
| Product Crew OS 自有内置 | 随本开源包一起发布的规则、模板、配置、SOP | 可以默认依赖 |
| 内置第三方 Skill | 已复制到 `third_party/skills/` 的开源 PM skill | 可以开箱调用，但必须保留原作者和许可证声明 |
| 插件 / MCP Skill | 来自 Codex 插件或外部 MCP，如 Figma、Pencil、Canva | 需要用户授权或对应插件可用 |
| 未验证建议能力 | router 里有能力名，但当前环境未确认安装 | 只能作为建议映射，必须提供 fallback 或模板兜底 |

主控教练不能把“router 写了某 skill”说成“已成功调用”。只有运行时真的读取了内置 skill、用户 skill、插件 skill 或对应模板，并按其规则完成处理，才可以说已调用对应能力。

内置第三方 skill 索引见 `bundled-skill-index.md`，第三方声明见 `../THIRD_PARTY_NOTICES.md`。

## 3. 0-43 已梳理 SOP 的 Skill 映射

| # | Stage | Primary Skill | Fallback Skill | 当前维护环境状态 | 缺失时兜底 |
| --- | --- | --- | --- | --- | --- |
| 0 | `project_intake` | `pm-workbench` | `product-manager-interrogation` | 内置第三方 skill，已打包到 `third_party/skills` | project card template |
| 1 | `request_triage` | `pm-workbench` | `product-manager-interrogation` | 内置第三方 skill，已打包到 `third_party/skills` | 项目状态栏 + triage note |
| 2 | `stakeholder_map` | `stakeholder-alignment-checker` | `pm-workbench` | 内置第三方 skill，已打包到 `third_party/skills` | stakeholder map template |
| 3 | `business_context` | `product-strategy` | `pm-workbench` / `strategy-doc` | 内置第三方 skill，已打包到 `third_party/skills`；`product-strategy` 有多个实现 | business context template |
| 4 | `existing_workflow_mapping` | `user-story-mapping` | `pm-workbench` | 内置第三方 skill，已打包到 `third_party/skills` | Mermaid / swimlane template |
| 5 | `evidence_inventory` | `pm-workbench` | `research-synthesis` | 内置第三方 skill，已打包到 `third_party/skills` | evidence inventory template |
| 6 | `problem_definition` | `problem-statement` | `define-problem-statement` | 内置第三方 skill，已打包到 `third_party/skills` | problem statement template + demand authenticity checklist |
| 7 | `user_segmentation` | `jtbd-analysis` | `define-jtbd-canvas` | 内置第三方 skill，已打包到 `third_party/skills` | user segmentation template |
| 8 | `research_plan` | `product-discovery` | `pm-workbench` | 内置第三方 skill，已打包到 `third_party/skills` | validation plan template |
| 9 | `interview_guide` | `product-discovery` | `summarize-interview` | 内置第三方 skill，已打包到 `third_party/skills` | interview guide template |
| 10 | `interview_synthesis` | `research-synthesis` | `user-research-synthesis` | 内置第三方 skill，已打包到 `third_party/skills` | research synthesis template |
| 11 | `persona_jtbd_journey` | `jtbd-analysis` | `jobs-to-be-done` / `define-jtbd-canvas` | 内置第三方 skill，已打包到 `third_party/skills` | JTBD / journey template |
| 12 | `opportunity_tree` | `opportunity-solution-tree` | `define-opportunity-tree` | 内置第三方 skill，已打包到 `third_party/skills` | opportunity tree template |
| 13 | `assumption_mapping` | `assumption-mapper` | `problem-clarity` | 内置第三方 skill，已打包到 `third_party/skills` | assumption map template |
| 14 | `value_sizing` | `feature-investment-advisor` | `value-vs-effort` | 内置第三方 skill，已打包到 `third_party/skills` | value sizing note template |
| 15 | `prioritization` | `prioritization-advisor` | `define-prioritization-framework` | 内置第三方 skill，已打包到 `third_party/skills` | prioritization stack template |
| 16 | `solution_exploration` | `pm-workbench` | `opportunity-solution-tree` / `value-vs-effort` | 内置第三方 skill，已打包到 `third_party/skills` | solution options brief template |
| 17 | `mvp_scope` | `scope-cutting` | `shape-up` | 内置第三方 skill，已打包到 `third_party/skills` | MVP scope template |
| 18 | `one_page_proposal` | `pm-workbench` | `strategy-doc` | 内置第三方 skill，已打包到 `third_party/skills` | one-page proposal template |
| 19 | `data_feasibility_precheck` | `product-analytics` | `measure-dashboard-requirements` | 内置第三方 skill，已打包到 `third_party/skills` | data contract template |
| 20 | `technical_feasibility_precheck` | `prd-critic` | `bmad-business-analyst` | 内置第三方 skill，已打包到 `third_party/skills` | tech feasibility note template |
| 21 | `compliance_precheck` | `pm-workbench` | `stakeholder-alignment-checker` | 内置第三方 skill，已打包到 `third_party/skills`；Legal 角色负责红线判断 | compliance risk note template |
| 22 | `core_flow_diagram` | `user-story-mapping` | `figma:figma-generate-diagram` | primary 已内置；Figma fallback 属于插件/授权能力 | Mermaid / flowchart template |
| 23 | `low_fi_prototype` | `pencil-design` | `figma:figma-use` | `pencil-design` 已内置；Figma fallback 属于插件/授权能力 | low-fi prototype brief template |
| 24 | `metrics_design` | `metrics-framework` | `north-star-metric` | 内置第三方 skill，已打包到 `third_party/skills` | metrics tree template |
| 25 | `instrumentation_plan` | `measure-instrumentation-spec` | `product-analytics` | primary 未内置；fallback 已内置；缺失时用 tracking plan 模板 | tracking plan template |
| 26 | `prd_outline` | `prd-development` | `prd-writing` | 内置第三方 skill，已打包到 `third_party/skills` | PRD outline template / Deep Artifact Pack |
| 27 | `prd_v0_draft` | `deliver-prd` | `prd-taskmaster` | 内置第三方 skill，已打包到 `third_party/skills` | PRD v0 template |
| 28 | `pm_self_review` | `prd-critic` | `product-manager-skills` | 内置第三方 skill，已打包到 `third_party/skills`；`product-manager-skills` 使用原作者许可证边界 | PRD self-review checklist |
| 29 | `internal_product_review` | `utility-pm-critic` | `stakeholder-alignment-checker` | 内置第三方 skill，已打包到 `third_party/skills` | review notes + decision log template |
| 30 | `design_review` | `develop-design-rationale` | `user-story-mapping` | primary 未验证建议能力；fallback 已内置；缺失时用设计评审模板 | design review checklist |
| 31 | `data_review` | `product-analytics` | `metric-dashboard` | 内置第三方 skill，已打包到 `third_party/skills` | data review checklist |
| 32 | `technical_pre_review` | `prd-critic` | `code-to-prd` | 内置第三方 skill，已打包到 `third_party/skills` | technical pre-review checklist |
| 33 | `formal_requirements_review` | `stakeholder-alignment-checker` | `pm-workbench` | 内置第三方 skill，已打包到 `third_party/skills` | formal requirements review checklist |
| 34 | `task_breakdown` | `prd-taskmaster` | `deliver-user-stories` | 内置第三方 skill，已打包到 `third_party/skills` | technical task breakdown template |
| 35 | `acceptance_criteria` | `deliver-acceptance-criteria` | `test-scenarios` | 内置第三方 skill，已打包到 `third_party/skills` | acceptance criteria / test scenario template |
| 36 | `development_tracking` | `pm-workbench` | `stakeholder-alignment-checker` | 内置第三方 skill，已打包到 `third_party/skills` | change log + decision note template |
| 37 | `integration_qa` | `test-scenarios` | `deliver-acceptance-criteria` | 内置第三方 skill，已打包到 `third_party/skills` | QA report / test scenario template |
| 38 | `launch_readiness` | `deliver-launch-checklist` | `test-scenarios` | primary 未验证建议能力；fallback 已内置；缺失时用上线清单模板 | launch checklist template |
| 39 | `training_enablement` | `pm-workbench` | `stakeholder-alignment-checker` | 内置第三方 skill，已打包到 `third_party/skills` | enablement SOP / FAQ template |
| 40 | `grey_release_pilot` | `experiment-design` | `trustworthy-experiments` | 内置第三方 skill，已打包到 `third_party/skills` | pilot plan template |
| 41 | `launch_monitoring` | `product-analytics` | `metric-dashboard` | 内置第三方 skill，已打包到 `third_party/skills` | launch monitoring notes / issue log template |
| 42 | `post_launch_review` | `pm-workbench` | `roadmap-planning` | 内置第三方 skill，已打包到 `third_party/skills` | postmortem template |
| 43 | `iteration_planning` | `roadmap-planning` | `prioritization-advisor` | 内置第三方 skill，已打包到 `third_party/skills` | iteration backlog / roadmap update template |

## 4. 后续 Router 需要持续核验的能力

以下能力出现在当前 router 中。普通 PM skill 已尽量内置；插件、MCP 或本机未找到的能力需要继续核验：

| 能力 | 当前处理方式 |
| --- | --- |
| `scope-cutting` / `shape-up` | 已内置第三方 skill；适合 `mvp_scope`，用于砍范围和设定 appetite |
| `pencil-design` / `figma:figma-use` / `figma:figma-generate-diagram` | `pencil-design` 已内置为能力说明；Figma 属于插件/外部工具能力，必须先确认用户授权和工具可用 |
| `measure-instrumentation-spec` | 未验证建议能力；缺失时 fallback 到 `product-analytics` 或埋点模板 |
| `develop-design-rationale` | 未验证建议能力；缺失时 fallback 到 `user-story-mapping` 或设计评审模板 |
| `deliver-launch-checklist` | 未验证建议能力；缺失时 fallback 到 `test-scenarios` 或上线清单模板 |

## 5. 调用失败时的标准话术

当 primary skill 缺失：

```text
这一步推荐使用 <primary skill>，但内置包或当前环境没有确认可用。我会先用 <fallback skill> 或对应 artifact 模板继续，保证流程不断。
```

当 primary 和 fallback 都缺失：

```text
当前环境没有可用的专项 skill。我会按 Product Crew OS 的 SOP 和 artifact 模板生成 v0，并把缺失能力记录到 skill gap，后续你可以选择安装或替换。
```

当用户自带 skill 更合适：

```text
你提供的 skill 更贴近你们公司的流程。我会把它作为当前 stage 的 overlay，但仍保留输入、输出、子 Agent 评审和 Stage Gate。
```

## 6. 开源包边界

Product Crew OS v0.1.x 发布的是：

- 主控教练规则。
- 44 个 SOP 卡片。
- Skill Router。
- 内置第三方 PM skill pack，位于 `third_party/skills/`。
- 子 Agent 边界和 context packet 机制。
- Artifact Workspace 模板。
- 回归测试和可迁移规则包。

它不保证所有 Figma/Pencil/MCP 插件或用户公司内部工具都随包可用。真正的产品能力来自：

```text
Product Crew OS 规则包 + 内置第三方 skill + 用户自有 skill overlay + 用户授权工具 + 项目 workspace
```
