# Workflow Orchestration Policy / 工作流编排规则

本文件把 Golden Case v4 固化为正式产品规则。它解决一个核心问题：

```text
用户前台必须简单，系统后台必须可回放。
```

## 1. 双层体验

### 1.1 用户前台

普通用户只应看到：

- 现在在判断什么。
- 本轮会交付什么。
- 本轮不承诺什么。
- 当前关键风险。
- 谁来把关。
- 用户需要拍什么板。
- 用户可以如何纠偏。

用户前台默认不展示：

- SOP 编号。
- Skill 名称。
- Gate ID。
- `role_key`。
- Invocation Ledger。
- Context Packet。
- raw review 路径。
- 后台 Trace。

如果用户主动要求查看依据，可以展示自然语言摘要或进入审计视图。

### 1.2 后台审计

后台必须记录：

- `input_id`
- `main_flow_id`
- `stage_id`
- `stage_candidates`
- `confidence`
- `sop_ids`
- `skill_router_log`
- `artifact_id`
- `artifact_version`
- `context_packet_refs`
- `invocation_ledger`
- `raw_review_records`
- `review_items`
- `user_decisions`
- `gate_status`
- `next_state`

后台复杂度不能丢失，因为它用于复盘、测试、审计和回归。

## 2. 默认执行模式

| 模式 | 用户语言 | 使用场景 | Gate 边界 |
| --- | --- | --- | --- |
| light | 快速判断 | 初步方向、低风险问题、用户要求快看 | 不能通过正式 Gate |
| standard | 标准推进 | 可评审产物、常规产品推进 | 可进入普通 Stage Gate |
| deep | 深度评审 | 正式 PRD、高风险上线、跨团队承诺、外部对齐 | 需要完整 Review Loop 和 raw review |

单轮默认最多组合 1-3 个 SOP。深度流程可以拆成多轮，不应一次塞满所有 SOP。

## 3. 风险与角色边界

主控教练只能识别风险候选，不能替专业角色下最终判断。

示例：

- 商业价值风险交给 Biz。
- 证据和真伪需求风险交给 Research。
- 可用性和路径风险交给 Design。
- 技术可行性和依赖风险交给 Tech。
- 指标口径和数据源风险交给 Data。
- 验收和回归风险交给 QA。
- 隐私、授权、公开边界风险交给 Legal。
- 培训和落地风险交给 Ops / CS。

## 4. Golden Case 通过边界

Golden Case 通过只代表某一类工作流编排样例可通过，不代表真实业务结论成立。

`flow_01_opportunity_discovery` 的 Golden Case 通过边界：

- 可以进入低成本验证。
- 不代表需求成立。
- 不代表 PRD 通过。
- 不代表 MVP 批准。
- 不代表法务合规认证。
- 不代表上线批准。

## 5. 合成样例防伪规则

合成样例必须明确：

```yaml
fixture_type: synthetic_case
real_runtime_claim: false
real_invocation_performed: false
simulation_label: synthetic_fixture
```

禁止把合成 fixture 写成真实子 Agent 调用。

真实 runtime 中必须记录真实工具返回的 `runtime_agent_id`、`runtime_nickname`、调用时间、Context Packet 和 raw review。

## 6. 材料与公开边界

真实用户材料、同事材料、客户材料、raw review 和角色记忆只能在用户授权范围内用于当前项目追溯与复评。

进入以下范围前必须单独授权并脱敏：

- 长期记忆。
- 角色风格训练。
- 模板沉淀。
- 公共规则包。
- 公开示例。
- 产品宣传。

Gate / Formal Gate 仅代表流程证据、角色评审与用户决策检查，不构成法务合规认证、律师审查、上线批准或对外合规背书。

## 7. 培训与覆盖边界

每个 Golden Case 必须声明覆盖哪个主流程。

如果只覆盖 `flow_01`，不能宣称 8 个主流程都已完整覆盖。

用户手册先讲 8 个主流程，培训手册再讲 SOP 编排，审计手册才讲 Trace / Context Packet / Invocation Ledger / raw review。

## 8. 实现覆盖边界

所有对外表述必须区分：

- SOP / Router 覆盖。
- Runtime Smoke 覆盖。
- Structured Review Loop 覆盖。
- 完整状态机 Golden Case 覆盖。

当前覆盖状态以 `workflow-implementation-coverage-v0.md` 和 `workflow-implementation-coverage-v0.yaml` 为准。

禁止把以下任一项单独说成“全流程已完成”：

- 44 个 SOP prompt eval 通过。
- 44 个 SOP runtime smoke 写入 SQLite。
- 一条 Golden Case 通过。
- 某个真实项目跑到低保真或 MVP 阶段。

允许的准确表述是：

> 已打通前段机会发现 + 子 Agent 评审机制的局部闭环；后续 workflow 状态机和编排仍需按阶段补齐。
