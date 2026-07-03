# Evaluation Test Plan / 测试用例与评估计划

本文件定义 Product Crew OS 的测试方法。它不是功能测试，而是 AI 产品流程测试：

- 每个 Stage 是否能命中。
- 每张 SOP 是否能产出正确 artifact。
- Skill Router 是否能选择 primary / fallback。
- 子 Agent 是否按边界出现。
- 非产品问题是否退出 Product Crew OS。
- Bad Case 是否能进入 Regression Test。

## 1. 测试层级

| 层级 | 名称 | 测什么 | 当前文件 |
| --- | --- | --- | --- |
| L0 | Package Validation | 文件完整、YAML/JSON 可解析、内置 skill 可索引 | `validate-package.rb` |
| L1 | Rule Regression | 子 Agent 调用契约、记忆、非产品退出、项目资产包 | `run-regression.rb` + `tests/scenarios/` |
| L2 | Prompt Eval | 44 个 SOP 的用户输入、stage、skill、artifact、agent、gate | `prompt-eval-cases.yaml` |
| L3 | External Benchmark | 第三方 PM benchmark 是否能被映射到 stage / skill / artifact / gate | `run-external-benchmark.rb` |
| L4 | Team Memory Eval | 团队角色记忆是否读取、注入、引用、回写和隔离 | `subagent-memory-runtime.yaml` + `memory-resume-after-context-loss.yaml` |
| L5 | Human Review | 评估回答是否像产品办公室、是否能用于真实工作 | 人工抽检 |
| L6 | Bad Case Evolution | 用户纠偏和失败是否进入测试集 | `evolution-notes.md` + 新 scenario |

## 2. 发布前最小测试命令

```bash
ruby product-crew-os-skill/tests/validate-package.rb
ruby product-crew-os-skill/tests/run-regression.rb --mock-delegate --check-only
ruby product-crew-os-skill/tests/run-external-benchmark.rb
```

通过标准：

- `validate-package: PASS`
- `run-regression: PASS`
- `run-external-benchmark: PASS`
- `prompt-eval-cases.yaml` 至少包含 44 个 case。
- 每个 case 必须有 `stage_id`、`user_input`、`expected.primary_skill`、`expected.required_artifacts`、`expected.stage_gate`。

## 3. Prompt Eval 人工评分表

每条 prompt case 由人工或评审模型打分：

| 评分项 | 0 分 | 1 分 | 2 分 |
| --- | --- | --- | --- |
| Domain Intent | 错误进入/退出 Product Crew OS | 不确定但有澄清 | 正确进入或退出 |
| Stage | stage 错误 | stage 接近但不精确 | stage 正确 |
| SOP | 没提 SOP 或路径错 | 部分执行 | 输入、输出、gate 都正确 |
| Skill | 未选或乱选 | primary/fallback 有一个正确 | primary/fallback 均合理 |
| Agent | 乱叫或漏叫关键角色 | 角色基本合理但边界不清 | 角色、边界、退出都正确 |
| Memory | 假装记得或污染记忆 | 读取部分记忆但来源不完整 | 读取、注入、引用、回写、隔离都正确 |
| Artifact | 只聊天回答 | artifact 方向对但不完整 | artifact 明确且可编辑 |
| Stage Gate | 没有过关判断 | 有判断但条件不清 | 通过/阻塞/回退明确 |
| Warmth | 生硬工具感 | 可接受 | 像产品办公室，有下一步 |

单条满分 18 分。

建议阈值：

- `>= 16`：通过。
- `13-15`：条件通过，需要补规则或示例。
- `<= 10`：Bad Case，进入 evolution loop。

## 4. Bad Case 入库规则

当出现以下情况，应新增或更新测试 case：

- 用户纠正 stage、SOP、skill、agent 或 artifact。
- 主控教练声称召唤 agent，但没有真实调用或模拟标注。
- 非产品请求被强行进入 Product Crew OS。
- 产物只在聊天中，没有写入 Artifact Workspace。
- 项目记忆覆盖旧决策或混入产品规则。
- 同一类问题连续出现 2 次以上。

新增 case 必须标注：

```yaml
source:
  type: "user_correction | self_run | subagent_review | cross_runtime | competitor_review | hypothesis"
  priority: "P0 | P1 | P2 | P3 | P4 | P5"
```

## 5. 44 个 SOP 覆盖策略

44 个 SOP 不是都需要复杂测试，但每个 SOP 至少有一条最小 prompt case。

覆盖要求：

- `stage_id` 覆盖 44/44。
- `macro_stage` 覆盖 10/10。
- 每个宏观阶段至少有 1 条高压边界 case。
- 每个可评审阶段至少验证一个 required/triggered role。
- 至少 1 条非产品退出 case。
- 至少 1 条低置信度澄清 case。
- 至少 1 条 primary skill 不可用后的 fallback case。
- 至少 1 条项目记忆恢复 case。

## 6. 团队记忆测试

团队记忆是否成功，不看底层子 Agent 聊天窗口是否自带长期记忆，而看主控教练是否完成：

```text
读取 agent-memory/{role_key}.md
-> 生成 memory_snapshot
-> 注入 agent-context-packet
-> 子 Agent 引用正确历史关注点
-> 评审后产生 memory_delta
-> 写回 Project Workspace
-> 不污染 Product Rule Memory
```

必测 case：

- `subagent-memory-runtime.yaml`：角色历史卡点是否被注入。
- `memory-resume-after-context-loss.yaml`：上下文压缩后是否能恢复项目状态。
- `project-asset-pack-persistence.yaml`：项目产物、评审项、决策、下一步是否落盘。
- `team-style-overlay-consent.yaml`：真实团队风格材料是否授权后才保存。

通过标准：

- 有 `role_key`。
- 有 `memory_snapshot`。
- 有 `source_ref`。
- 有 `memory_delta`。
- 有 `scope`，且只写入 project / user overlay / product rule 中正确的一类。
- 如果没有历史记忆，必须说明为空，不能编造。

## 7. 第三方 Benchmark 接入

`run-external-benchmark.rb` 可读取第三方 PM benchmark 目录，默认使用内置 `third_party/skills/pm-workbench/benchmark`。

它当前验证的是“外部真实 PM 场景是否能进入 Product Crew OS 的 stage / skill / artifact / gate 映射”，不是替代人工打分。

它也支持负例测试。比如 WorkBench 的办公任务用例应被识别为 `domain_exit`，不能强行套入产品 SOP。

输出位置：

```text
tests/results/external-benchmark-YYYYMMDD-HHMMSS/
```

输出文件：

- `external-benchmark-routes.yaml`
- `external-benchmark-report.md`

当用户提供 WorkBuddy 或其他 GitHub benchmark 时，可用相同命令指定目录：

```bash
ruby product-crew-os-skill/tests/run-external-benchmark.rb /path/to/external/benchmark /path/to/output
```

## 8. 后续自动化方向

当前 `prompt-eval-cases.yaml` 是测试数据源。下一步可以新增一个 runner：

```text
prompt-eval-cases.yaml
-> 调用当前 Product Crew OS runtime
-> 解析 route_decision JSON
-> 对比 expected
-> 输出 stage / skill / agent / artifact / gate 分数
```

输出建议：

```text
stage_accuracy: 0.91
skill_accuracy: 0.84
agent_routing_precision: 0.88
artifact_completion_rate: 0.93
stage_gate_explicit_rate: 0.95
prompt_regression_pass_rate: 0.89
```
