# Workflow Orchestration Map v0 / 主流程编排地图

更新时间：2026-07-10

本文件解释 `workflow-orchestration-map-v0.yaml` 的用途和边界。

## 1. 为什么新增这个文件

之前 Product Crew OS 已经有：

- 44 个 SOP 卡片。
- 44 个 Skill Router 映射。
- 44 个 Prompt Eval。
- 44 个 Runtime Smoke。
- 1 条局部 Golden Case。

但这些能力不能自动说明“10 大主流程完整编排已完成”。

原因是：SOP 是细阶段能力，Runtime Smoke 是写入能力，Prompt Eval 是路由能力；而完整主流程编排还需要证明一个产品主流程可以端到端回放，包括 stage 顺序、artifact 链、Skill 命中、子 Agent 评审、用户决策、Stage Gate、项目记忆和导出。

所以新增 `workflow-orchestration-map-v0.yaml` 作为 10 大主流程的编排计数器。

## 2. 当前结论

当前准确状态：

| 项 | 当前值 |
| --- | --- |
| 10 大主流程总数 | 10 |
| 完整主流程编排 | 1/10 |
| 已完成主流程证据 | flow_01 opportunity discovery complete |
| Golden Case | 2 条：1 条局部样例 + 1 条 flow_01 完整主流程 |

允许说：

> flow_01 机会发现已具备完整主流程 Golden Case；当前 10 大主流程完整编排为 1/10。

不允许说：

> 10 大主流程已经完整跑通。

## 3. 什么叫完整主流程

一个主流程只有同时满足以下条件，才可以记为完整：

1. `flow_map_defined`：主流程 stage、SOP、artifact、role、gate 已定义。
2. `state_machine_path_defined`：状态机路径可回放。
3. `artifact_chain_defined`：关键 artifact 和版本规则明确。
4. `primary_skill_assertions_defined`：能断言 primary / fallback / template_degraded。
5. `required_and_triggered_roles_defined`：Required / Triggered 角色明确。
6. `invocation_ledger_assertions_defined`：真实调用、模拟调用、runtime_blocked 可追踪。
7. `gate_evidence_defined`：pass / conditional_pass / block / rollback 条件明确。
8. `golden_case_replayable`：有自动化 Golden Case 断言上述记录。

`run-release-gate.py` 的 44 条路由通过也不等于满足这些条件。

## 4. 10 大主流程

| Flow | 名称 | 当前状态 | 说明 |
| --- | --- | --- | --- |
| `flow_01_opportunity_discovery` | 机会发现 | complete | 已补齐 6 个机会发现子阶段、artifact 链、primary skill 断言、角色触发、Gate 与负向路径 |
| `flow_02_user_research` | 用户研究 | partial | 有局部 evidence / runtime 证据，但缺完整用户研究 Golden Case |
| `flow_03_problem_framing` | 问题定义 | not_started | 缺完整 Golden Case |
| `flow_04_requirement_analysis` | 需求分析 | partial | 有局部项目实践和 runtime 证据，但缺完整 Golden Case |
| `flow_05_solution_design` | 方案设计 | partial | 低保真等有局部实践，但缺完整方案设计 Golden Case |
| `flow_06_prd_drafting` | PRD 起草 | not_started | 缺 PRD outline -> v0 -> self-review 闭环 |
| `flow_07_cross_functional_review` | 跨职能评审 | partial | 有 review loop 测试，但缺主流程 Golden Case |
| `flow_08_delivery_planning` | 交付规划 | not_started | 缺任务到验收闭环 |
| `flow_09_launch_readiness` | 上线准备 | not_started | 缺 go/no-go、灰度、回滚完整样例 |
| `flow_10_post_launch_review` | 复盘迭代 | not_started | 缺监控、复盘、迭代计划闭环 |

## 5. Skill 成功口径

主流程编排必须区分：

| `skill_status` | 含义 |
| --- | --- |
| `primary_hit` | primary skill 成功命中 |
| `fallback_hit` | fallback skill 成功命中 |
| `template_degraded` | 仅使用 artifact template 兜底，必须记 degraded |
| `missing` | 没有可用 skill 或模板 |
| `runtime_blocked` | runtime 限制导致无法调用 |

`template_degraded` 可以保证流程不断，但不能算 primary skill 成功。

## 6. Runner

当前不再单独维护 Ruby runner；编排审计由 Python Release Gate 覆盖：

```bash
python3 product-crew-os-skill/tests/run-release-gate.py
```

它当前做编排计数验证：

- 能读取 `workflow-orchestration-map-v0.yaml`。
- 能识别 10 大主流程。
- 能确认当前完整主流程是 1/10。
- 能确认 flow_01 有完整 Golden Case。
- 能确认其余 9 个 flow 没有被误标成 complete，并区分 partial / not_started。

后续每补一条完整 Golden Case，runner 再把对应 flow 从 `not_started / partial` 推进到 `complete`。

## 7. 后续实现顺序

建议顺序：

1. 完成 Block 0：编排地图 + runner + validate-package 接入。
2. 已完成：补 `flow_01_opportunity_discovery_full.yaml`，把 0/10 推到 1/10。
3. 补 `flow_02_user_research_full.yaml`。
4. 补 `flow_03_problem_framing_full.yaml`。
5. 补 `flow_04_requirement_analysis_full.yaml`。
6. 补 `flow_05_solution_design_full.yaml`。
7. 补 `flow_06_prd_drafting_full.yaml`。
8. 补 `flow_07_cross_functional_review_full.yaml`。
9. 补 `flow_08_delivery_planning_full.yaml`。
10. 补 `flow_09_launch_readiness_full.yaml`。
11. 补 `flow_10_post_launch_review_full.yaml`。

每完成一个 flow，再更新 `workflow-implementation-coverage-v0.yaml` 的完成计数。
