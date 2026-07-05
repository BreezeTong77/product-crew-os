# Evaluation Metrics / 评估指标定义

本文件定义 Product Crew OS 的效果验证指标。它用于回答：

- 主控教练是否判断对了阶段。
- SOP、Skill、子 Agent 和 Artifact 是否被正确路由。
- Review Loop 是否真的降低了幻觉和错误推进。
- Bad Case 是否能进入持续迭代闭环。

## 1. 指标分层

| 层级 | 指标目标 | 典型问题 |
| --- | --- | --- |
| L0 Package Quality | 发布包是否完整、可安装、可解析 | 文件缺失、YAML/JSON 错误、内置 skill 缺失 |
| L1 Routing Quality | 输入是否命中正确 stage / SOP / skill | Stage 判断错、非产品问题被强行路由 |
| L2 Review Quality | 子 Agent 是否必要、准确、有边界 | 该叫的人没叫、不该叫的人出现、假装真实调用 |
| L3 Artifact Quality | 是否产出正确且可继续编辑的产物 | 只在聊天里回答、缺少 decision log、artifact 太薄 |
| L4 Team Memory Quality | 团队角色记忆是否读取、注入、引用和回写成功 | 子 Agent 忘记上次卡点、凭空说记得、记忆污染 |
| L5 Project Memory Quality | 项目记忆是否可追溯、不覆盖、不污染 | 项目内容写进公共规则、旧决策覆盖新决策 |
| L6 Evolution Quality | Bad Case 是否被复盘并进入测试 | 同类错误重复出现、没有回归用例 |

## 2. 核心指标

| 指标 | 定义 | 计算方式 | 数据来源 | Alpha 目标 | 触发 Bad Case 的条件 |
| --- | --- | --- | --- | --- | --- |
| Stage 命中率 | 主控教练识别的 stage 是否符合人工标注 | correct_stage / total_product_cases | prompt eval cases, user correction, event-log | >= 85% | 连续 3 次同类场景误判 |
| Domain Gate 准确率 | 是否正确判断 Product Crew OS 应不应该接管 | correct_domain_decisions / total_turns | prompt eval cases, external benchmark, user correction | >= 90% | 非产品问题被强行进 SOP，或产品问题被退出 |
| SOP 命中率 | stage 命中后是否读取并执行对应 SOP 卡片 | correct_sop / routed_cases | route decision, SOP id, artifact metadata | >= 90% | 命中 stage 但跳过 SOP |
| Skill 命中率 | 是否选择了正确 primary/fallback skill 或模板 | correct_skill_or_template / routed_cases | skill_selected event, skill-stage-router | >= 80% | skill 不适用且未 fallback |
| 子 Agent 召唤准确率 | 必要角色是否出现，不必要角色是否缺席 | correct_agent_routing / review_cases | agent ledger, stage-boundary-matrix | >= 85% | 假装召唤、全员乱入、关键角色缺席 |
| 子 Agent 调用诚实率 | 是否清楚区分真实调用、模拟视角和未调用 | honest_invocation_labels / agent_outputs | invocation ledger, response QA | 100% | 没真实调用却说已拉起 |
| 评审批次覆盖率 | 当 SOP 需要多个角色时，是否通过有序批次覆盖 required 和 gate-blocking roles | covered_required_roles / required_roles_across_batches | review batch plan, agent ledger, stage-boundary-matrix | >= 95% | 因单批次上限漏掉必要角色 |
| Review 通过率 | 评审后 artifact 是否可进入下一阶段 | pass_or_conditional_pass / review_cases | review-items, decision-log, stage gate | 观察值 | 评审意见没有转成修改项 |
| Artifact 完成率 | 本 stage 必要 artifact 是否生成或更新 | completed_required_artifacts / required_artifacts | artifact-index, project-state | >= 90% | 只聊天回答，没有可编辑源文件 |
| Stage Gate 通过率 | 阶段门是否明确通过、条件通过、阻塞或回退 | explicit_gate_decisions / gated_cases | decision-log, next-actions | >= 95% | 没说清能否进入下一阶段 |
| 用户纠偏率 | 用户纠正 stage、skill、agent、artifact 或事实的比例 | user_correction_events / total_turns | user_correction event, evolution-notes | 越低越好 | 同类纠偏重复出现 |
| 幻觉/越权率 | 假数据、假审批、假调用、假来源出现比例 | guardrail_failures / evaluated_turns | guardrail_failed event | 0 high-impact | 假装真实调用或编造外部数据 |
| Workflow 完成率 | 用户从当前 stage 推进到下一可执行动作的比例 | turns_with_next_action / product_turns | response QA, next-actions | >= 90% | 没有下一步动作 |
| 项目记忆命中率 | 后续回溯时是否能找到相关 artifact / decision | successful_memory_hits / memory_queries | project asset pack, source-ledger | >= 80% | 找不到已确认决策 |
| Context Packet 注入率 | 召唤子 Agent 前是否注入 stage、artifact、决策、风险和记忆摘要 | complete_context_packets / agent_invocations | agent-context-packet, invocation ledger | >= 95% | 子 Agent 没拿到当前 artifact 或历史卡点 |
| 团队角色记忆召回率 | 子 Agent 是否引用了正确的历史关注点、上次阻塞项或团队风格 | correct_role_memory_references / memory_agent_cases | agent-memory, context packet, review output | >= 80% | 忘记已存在的角色记忆，或引用不存在的记忆 |
| Memory Delta 写回率 | 评审结束后是否把可复用结论写入 review items、decision log 或 agent memory delta | written_memory_deltas / memory_relevant_reviews | memory delta queue, project workspace | >= 90% | 评审意见只留在聊天里 |
| 记忆来源可追溯率 | 每条长期记忆是否带 source_ref、scope、confidence 和 owner | traceable_memory_items / memory_items | source-ledger, event-log, agent-memory | 100% | 记忆没有来源或范围 |
| 记忆隔离通过率 | 产品规则、用户偏好、项目记忆是否保持隔离 | isolated_memory_writes / memory_writes | memory writer, scope field, package review | 100% | 项目内容写进 README / 产品规则 / 公共 skill |
| 防覆盖通过率 | 更新记忆或 artifact 时是否保留旧版本、checkpoint 或 event log | versioned_updates / update_events | checkpoints, event-log, artifact versions | >= 95% | 覆盖旧决策且无法回滚 |
| 团队风格授权率 | 真实同事语气、会议纪要、邮件材料进入风格记忆前是否获得授权 | consented_style_writes / style_memory_writes | consent record, team-style-overlay | 100% | 未授权保存真实团队材料 |
| 外部 Benchmark 通过率 | 第三方正向/负向测试是否正确进 SOP 或退出 | passed_external_cases / external_cases | run-external-benchmark.rb | >= 90% | WorkBench 类办公任务被强行进产品流程 |
| Bad Case 修复率 | 已登记 Bad Case 是否转化为规则或测试 | fixed_bad_cases / logged_bad_cases | evolution-notes, regression scenarios | >= 70% | Bad Case 没有 owner 或测试 |
| Prompt Regression 通过率 | 固定 prompt 测试集是否稳定通过 | passed_prompt_cases / total_prompt_cases | prompt-eval-cases.yaml | >= 90% | 新版本低于上版 |

## 3. 事件埋点建议

运行时应尽量记录以下事件，后续可进入 `event-log.jsonl`：

```json
{
  "event_type": "stage_detected",
  "turn_id": "t-001",
  "domain_intent": "product_work",
  "stage_id": "low_fi_prototype",
  "confidence": 0.86,
  "matched_signals": ["用户要求画原型图", "用户提供截图"],
  "source": "semantic_stage_router"
}
```

```json
{
  "event_type": "skill_selected",
  "turn_id": "t-001",
  "stage_id": "low_fi_prototype",
  "primary_skill": "pencil-design",
  "fallback_skill": "figma:figma-use",
  "selected": "pencil-design",
  "fallback_used": false
}
```

```json
{
  "event_type": "agent_summoned",
  "turn_id": "t-001",
  "stage_id": "low_fi_prototype",
  "role_key": "Design",
  "trigger_reason": "SOP requires design review for prototype artifact",
  "real_invocation_performed": true
}
```

```json
{
  "event_type": "memory_snapshot_built",
  "turn_id": "t-001",
  "stage_id": "low_fi_prototype",
  "role_key": "Design",
  "project_role_memory_exists": true,
  "included_last_objections": true,
  "source_refs": ["agent-memory/Design.md#latest-review"]
}
```

```json
{
  "event_type": "memory_delta_written",
  "turn_id": "t-001",
  "role_key": "Design",
  "target_scope": "project",
  "target": "agent-memory/Design.md",
  "source_ref": "review-items.yaml#RI-12",
  "confidence": "confirmed"
}
```

```json
{
  "event_type": "external_benchmark_case_evaluated",
  "case_id": "workbench-project-management-001",
  "domain_intent": "operational_task",
  "route_status": "domain_exit",
  "expected_route_status": "domain_exit"
}
```

```json
{
  "event_type": "stage_gate_decision",
  "turn_id": "t-001",
  "stage_id": "low_fi_prototype",
  "decision": "conditional_pass",
  "conditions": ["补充空状态", "确认底部导航交互"],
  "next_stage": "design_review"
}
```

## 4. 测试集来源分级

Bad Case 和测试 case 的来源需要标注来源等级：

| 来源等级 | 来源 | 价值 |
| --- | --- | --- |
| P0 | 真实用户纠偏或真实项目使用 | 最高，优先进入回归测试 |
| P1 | 主控教练连续自测 / Codex 跑完整流程 | 高，可发现流程断点 |
| P2 | 子 Agent / reviewer 评审发现 | 高，可发现角色边界和评审质量问题 |
| P3 | Claude / Cursor / 其他运行环境对比 | 中，可发现迁移兼容问题 |
| P4 | 竞品或开源项目对比 | 中，可发现表达、结构和包装问题 |
| P5 | 主观假设 | 低，只能作为待验证 case |

## 5. 评估节奏

| 节奏 | 要做什么 | 输出 |
| --- | --- | --- |
| 每次发布前 | 跑 package validation、regression、prompt eval schema check | release QA note |
| 每次团队记忆规则变更后 | 跑 subagent_memory_runtime、memory_resume、project_asset_pack_persistence | memory QA note |
| 每次重大规则变更后 | 跑 44 SOP prompt eval，比较通过率变化 | regression diff |
| 每次接入第三方测试集后 | 跑正向 PM benchmark 和负向办公任务 benchmark | external benchmark report |
| 每周 | 复盘 user correction、guardrail failure、unresolved risk | evolution-notes.md |
| 每月 | 检查低频 SOP 是否合并，高风险 SOP 是否拆分 | SOP change proposal |

## 6. 团队记忆是否成功的判断

团队记忆不是看“子 Agent 聊天窗口有没有记住”，而是看主控教练是否完成了这条链路：

```text
读取角色配置和项目角色记忆
-> 压缩成 memory_snapshot
-> 注入 agent-context-packet
-> 子 Agent 只引用 packet 中的内容
-> 评审后生成 review item / decision / memory delta
-> 写回 Project Workspace，并带 source_ref、scope、confidence
```

验收问题：

- 本轮召唤的 role_key 是否正确。
- `memory_snapshot.project_role_memory.exists` 是否真实反映文件状态。
- 子 Agent 是否引用了“上次卡过的问题”，且该问题能在 agent-memory 或 decision-log 中找到来源。
- 如果没有历史记忆，是否明确说“本项目暂无该角色历史记忆”。
- 评审后是否产生 memory delta，而不是只停在聊天里。
- 记忆写入是否只进入 project 或 user overlay，没有污染 Product Rule Memory。
- 真实团队材料是否在授权后才进入 team-style-overlay。

## 7. 面试表达口径

可以这样说：

> 我没有只把 Product Crew OS 做成一套 Prompt，而是补了评估闭环。当前已有包完整性校验、19 个回归场景、44 个 SOP 的 Prompt Eval 测试集和第三方 benchmark runner；指标上定义了 Stage 命中率、SOP 命中率、Skill 命中率、子 Agent 召唤准确率、Context Packet 注入率、团队角色记忆召回率、Artifact 完成率、Bad Case 修复率和 Prompt Regression 通过率。这样每次迭代不是凭感觉改，而是能看到路由、评审、产物、团队记忆和外部边界的质量变化。
