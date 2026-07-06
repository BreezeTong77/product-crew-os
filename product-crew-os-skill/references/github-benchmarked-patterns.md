# 开源对标借鉴清单（非抄袭）

本页用于记录“别人做了什么 → 我们现在如何借鉴”。目的是让 44 个 SOP 落在统一机制和验证闭环上，避免靠开发者记忆做判断。

## 一、借鉴方向

### 1) 代理编排型框架
- 流程状态机优先于自由对话。
- 子角色边界、角色召唤、批次控制与失败退化必须可解释。
- 不能“硬过阶段”，阻塞要落盘且显式提示。

### 2) PM 流程技能库
- Skill 与 Skill Router 解耦，按职责调用。
- 任务模板与输出 schema 固定，减少临时发挥。
- 通过测试样本回归流程行为。

### 3) 可观测闭环平台
- 每个节点产出指标记录（Stage 命中率、Skill 命中率、Agent 命中率）。
- Bad Case 回流，形成 `run-loop-50-cases` 的闭环。
- 评审冲突、阻塞、等待和超时必须可查。

## 二、仓库级对照落点

| 模块 | 借鉴机制 | 我们落地文件 | 当前验证 |
| --- | --- | --- | --- |
| 流程编排 | Flow-first state machine 与可重放流程 | [workflow-map.md](workflow-map.md)、[stage-boundary-matrix.md](stage-boundary-matrix.md) | L0、L5 |
| 评审闭环 | must-fix 阻塞 + 冲突矩阵 + 用户决策回路 | [structured-review-loop.md](structured-review-loop.md)、[subagent-memory-runtime-contract.md](subagent-memory-runtime-contract.md) | L6a、L7 |
| 路由与回退 | Stage 分类 + fallback Skill + 无法召回降级策略 | [skill-router.md](skill-router.md)、[semantic-stage-router.md](semantic-stage-router.md) | L3a、L6 |
| 质量评估 | 评分指标统一 + 外部案例映射 | [evaluation-metrics.md](evaluation-metrics.md)、[evaluation-test-plan.md](../tests/evaluation-test-plan.md) | L3a、L8 |

### 证据追踪

- 流程图映射：`workflow-map.md`  
- 指标映射：`evaluation-metrics.md`  
- 任何 `run-*` 命令未过时，不允许跳过本轮。

## 三、44 SOP 对标矩阵（对照 + 验证）

| # | SOP | 借鉴机制 | 当前落点 | 验证 |
| --- | --- | --- | --- | --- |
| 0 | Project intake | 项目接入最小闭环 | [workflow-sop-library.md](workflow-sop-library.md)、[project-state.json](../templates/project-state.json) | L0、L1 |
| 1 | Request triage | 意图归一与非产品退出机制 | [semantic-stage-router.md](semantic-stage-router.md)、[stage-boundary-matrix.md](stage-boundary-matrix.md) | L3a、L2 |
| 2 | Stakeholder map | 角色权责清单化 | [stage-boundary-matrix.md](stage-boundary-matrix.md)、[stakeholder-boundaries.yaml](../config/stakeholder-boundaries.yaml) | L1、L2 |
| 3 | Business context | 业务目标可追责表达 | [subagent-invocation-contract.md](subagent-invocation-contract.md)、`project-asset-pack` business context 区块 | L2、L8 |
| 4 | Existing workflow mapping | 流程图文档标准化 | [workflow-sop-library.md](workflow-sop-library.md)、[evidence-inventory.md](../templates/artifacts/evidence-inventory.md) | L5、L6 |
| 5 | Evidence inventory | 证据/推断分层 | [workflow-sop-library.md](workflow-sop-library.md)、[project-memory-index-architecture.md](project-memory-index-architecture.md) | L7、L8 |
| 6 | Problem definition | 问题陈述与方案分离 | [workflow-sop-library.md](workflow-sop-library.md)、[structured-review-loop.md](structured-review-loop.md) | L2、L6 |
| 7 | User segmentation | 主用户边界与服务边界 | [workflow-sop-library.md](workflow-sop-library.md)、[project-asset-pack.md](project-asset-pack.md) | L2、L3 |
| 8 | Research plan | 研究计划模板化 | [workflow-sop-library.md](workflow-sop-library.md)、[run-external-benchmark.rb](../tests/run-external-benchmark.rb) | L3、L6 |
| 9 | Interview guide | 访谈问题标准化 | [workflow-sop-library.md](workflow-sop-library.md)、[templates/artifacts/evidence-inventory.md](../templates/artifacts/evidence-inventory.md) | L2、L6 |
| 10 | Interview synthesis | 原话/洞察可追踪 | [workflow-sop-library.md](workflow-sop-library.md)、[project-asset-pack.md](project-asset-pack.md) | L2、L6 |
| 11 | Persona / JTBD / Journey | 动机链路到决策链路 | [workflow-sop-library.md](workflow-sop-library.md)、[semantic-stage-router.md](semantic-stage-router.md) | L2、L3 |
| 12 | Opportunity tree | 机会拆解与优先化入口 | [workflow-sop-library.md](workflow-sop-library.md)、[run-loop-50-cases.rb](../tests/run-loop-50-cases.rb) | L2、L6 |
| 13 | Assumption mapping | 高风险假设抽取与验证 | [evolution-policy.yaml](../config/evolution-policy.yaml)、[badcase-loop-50.md](../tests/badcase-loop-50.md) | L6、L9 |
| 14 | Value sizing | 价值-成本-置信度建模 | [skill-router.md](skill-router.md)、[evaluation-metrics.md](evaluation-metrics.md) | L3a、L8 |
| 15 | Prioritization | 可争议排序和阻塞记录 | [workflow-sop-library.md](workflow-sop-library.md)、[decision-log.md](../templates/project-workspace/decision-log.md) | L2、L6 |
| 16 | Solution exploration | 方案对比与选择透明化 | [workflow-sop-library.md](workflow-sop-library.md)、[structured-review-loop.md](structured-review-loop.md) | L6a、L6 |
| 17 | MVP scope | MVP 与非目标边界固定 | [workflow-sop-library.md](workflow-sop-library.md)、[templates/artifacts/mvp-scope.md](../templates/artifacts/mvp-scope.md) | L2、L3 |
| 18 | One-page proposal | 提案 artifact 的评审前格式 | [workflow-sop-library.md](workflow-sop-library.md)、[examples/first-run-demo.md](../../examples/first-run-demo.md) | L2、L3 |
| 19 | Data feasibility precheck | 数据契约与可执行边界 | [templates/artifacts/data-contract.md](../templates/artifacts/data-contract.md)、[project-memory-index-architecture.md](project-memory-index-architecture.md) | L5、L7 |
| 20 | Technical feasibility precheck | 技术边界、依赖和风险先露 | [templates/artifacts/tech-feasibility-note.md](../templates/artifacts/tech-feasibility-note.md)、[runtime-adapter-contract.md](runtime-adapter-contract.md) | L5、L3 |
| 21 | Compliance precheck | 合规边界的显式承诺 | [evolution-policy.yaml](../config/evolution-policy.yaml)、[subagent-invocation-contract.md](subagent-invocation-contract.md) | L7、L8 |
| 22 | Core flow diagram | 关键流程图最小闭环表达 | [workflow-sop-library.md](workflow-sop-library.md)、[templates/artifacts/low-fi-prototype-brief.md](../templates/artifacts/low-fi-prototype-brief.md) | L5、L6 |
| 23 | Low-fi prototype | 原型前后评审联动 | [templates/artifacts/low-fi-prototype-brief.md](../templates/artifacts/low-fi-prototype-brief.md)、[structured-review-loop.md](structured-review-loop.md) | L6a、L6 |
| 24 | Metrics design | 指标树、护栏、复盘窗口 | [evaluation-metrics.md](evaluation-metrics.md)、[templates/artifacts/acceptance-criteria.md](../templates/artifacts/acceptance-criteria.md) | L8 |
| 25 | Instrumentation plan | 事件字典和 trace 结构 | [evolution-policy.yaml](../config/evolution-policy.yaml)、[runtime-adapter-contract.md](runtime-adapter-contract.md) | L3a、L5 |
| 26 | PRD outline | 可审阅结构先行 | [templates/artifacts/prd-review-notes.md](../templates/artifacts/prd-review-notes.md)、[workflow-sop-library.md](workflow-sop-library.md) | L5、L6 |
| 27 | PRD v0 draft | 草稿可追溯、非一次性输出 | [templates/artifacts/prd-review-notes.md](../templates/artifacts/prd-review-notes.md)、[run-external-benchmark.rb](../tests/run-external-benchmark.rb) | L3、L5 |
| 28 | PM self-review | 自检清单可回放 | [manual-score-cases.yaml](../tests/manual-score-cases.yaml)、[run-review-loop-e2e.rb](../tests/run-review-loop-e2e.rb) | L8、L6a |
| 29 | Internal product review | 全量评审与 must-fix 分流 | [structured-review-loop.md](structured-review-loop.md)、[templates/artifacts/review-session.md](../templates/artifacts/review-session.md) | L6a、L6 |
| 30 | Design review | 设计视角的独立反馈 | [experience/stage-rituals.md](experience/stage-rituals.md)、[templates/artifacts/review-session.md](../templates/artifacts/review-session.md) | L6a、L6 |
| 31 | Data review | 数据指标验证边界 | [templates/artifacts/test-scenario-library.md](../templates/artifacts/test-scenario-library.md)、[templates/artifacts/acceptance-criteria.md](../templates/artifacts/acceptance-criteria.md) | L3a、L8 |
| 32 | Technical pre-review | 技术风险先审清单 | [templates/artifacts/tech-feasibility-note.md](../templates/artifacts/tech-feasibility-note.md)、[runtime-adapter-contract.md](runtime-adapter-contract.md) | L3、L5 |
| 33 | Formal requirements review | Stage Gate 与多角色签入 | [structured-review-loop.md](structured-review-loop.md)、[gate-policy.md](gate-policy.md) | L6a、L6 |
| 34 | Task breakdown | 任务粒度与责任可执行 | [templates/artifacts/technical-task-breakdown.md](../templates/artifacts/technical-task-breakdown.md)、[templates/project-state.json](../templates/project-state.json) | L5、L6 |
| 35 | Acceptance criteria | 验收标准 schema 固定 | [templates/artifacts/acceptance-criteria.md](../templates/artifacts/acceptance-criteria.md)、[workflow-sop-library.md](workflow-sop-library.md) | L3、L5 |
| 36 | Development tracking | 变更事件与阻塞复盘 | [templates/project-workspace/artifact-diff.md](../templates/project-workspace/artifact-diff.md)、[project-state.json](../templates/project-state.json) | L7、L9 |
| 37 | Integration / QA | 联调与发布风险分级 | [templates/artifacts/test-scenario-library.md](../templates/artifacts/test-scenario-library.md)、[run-runtime-smoke.rb](../tests/run-runtime-smoke.rb) | L4、L5 |
| 38 | Launch readiness | 上线前门禁清单 | [templates/artifacts/launch-checklist.md](../templates/artifacts/launch-checklist.md)、[gate-policy.md](gate-policy.md) | L6a、L3 |
| 39 | Training / enablement | 组织接收度和材料生成 | [templates/project-workspace/source-ledger.md](../templates/project-workspace/source-ledger.md)、[templates/project-workspace/timeline.md](../templates/project-workspace/timeline.md) | L5、L7 |
| 40 | Grey release / pilot | 试点、回退、迭代学习 | [evaluation-metrics.md](evaluation-metrics.md)、[templates/project-workspace/artifact-index.yaml](../templates/project-workspace/artifact-index.yaml) | L8、L6 |
| 41 | Launch monitoring | 线上指标与人工介入边界 | [evolution-policy.yaml](../config/evolution-policy.yaml)、[run-runtime-smoke.rb](../tests/run-runtime-smoke.rb) | L7、L8 |
| 42 | Post-launch review | 复盘结果入下轮输入 | [templates/artifacts/postmortem.md](../templates/artifacts/postmortem.md)、[badcase-loop-50.md](../tests/badcase-loop-50.md) | L8、L9 |
| 43 | Iteration planning | 回归结论驱动下一周期 | [badcase-loop-50.md](../tests/badcase-loop-50.md)、[run-loop-50-cases.rb](../tests/run-loop-50-cases.rb) | L6、L9 |

## 四、持续更新机制

新增外部可复用机制时，按以下顺序补档：
1. 在本页新增行并标注来源机制。  
2. 在 refs/config/tests 对应规则落实现。  
3. 添加至少 1 条验证 case。  
4. 记录到 `CHANGELOG` 与 `badcase-loop-50.md`（如有新边界）。

## 五、采纳与合规规则（避免误用）

- 不直接复用第三方文本内容。  
- 不直接复用对方目录与变量命名。  
- 所有借鉴必须先落到 `references` + `runtime` + `tests` 三条线，再发版。  
