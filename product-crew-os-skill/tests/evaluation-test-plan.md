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
| L3a | Semantic Routing Eval | 用 gold label 计算 Domain / Stage / Skill / Agent 命中率 | `run-routing-eval.rb` + `external-benchmark-cases.yaml` |
| L3b | Embedding RAG Dry Run | 验证 `pco_rules` 公共规则索引、Input Scope Gate、source_ref 和 RAG hit@k | `run-embedding-rag-dry-run.rb` + `embedding-rag-policy.yaml` |
| L3c | RAG Ingestion Contract | 验证 OCR、语义 overlap chunk、开源 embedding、vector store、增量更新、维护和监控契约 | `run-rag-ingestion-contract.rb` + `embedding-rag-policy.yaml` + `embedding-rag-schema.sql` |
| L3d | Local Open-Source Embedding Provider Contract | 验证本地 BGE 开源 embedding provider 是否真实可用；缺依赖时必须 runtime_blocked，不能算通过 | `run-local-open-source-embedding-provider-contract.rb` |
| L4 | Runtime Smoke | SQLite runtime、项目资产包、Context Packet、Obsidian-compatible 导出是否可运行 | `run-runtime-smoke.rb` |
| L5 | SOP E2E Smoke | 44 个 SOP 是否能真实写入 runtime，并产生可观测记录 | `run-sop-e2e-smoke.rb` |
| L6 | Loop 50 Bad Case | 44 个 SOP + 6 个高风险 Bad Case 是否闭环通过，是否写入测试账本 | `run-loop-50-cases.rb` + `badcase-loop-50.md` + `test-ledger.md` |
| L6a | Review Loop E2E | 用户决策闭环、must-fix 阻塞、真实 raw review 透传、角色记忆注入 | `run-review-loop-e2e.rb` |
| L7 | Team Memory Eval | 团队角色记忆是否读取、注入、引用、回写和隔离 | `subagent-memory-runtime.yaml` + `memory-resume-after-context-loss.yaml` |
| L8 | Human Review | 评估回答是否像产品办公室、是否能用于真实工作 | `manual-score-cases.yaml` + 人工抽检 |
| L9 | Bad Case Evolution | 用户纠偏和失败是否进入测试集 | `evolution-notes.md` + 新 scenario |

## 2. 发布前最小测试命令

```bash
ruby product-crew-os-skill/tests/validate-package.rb
ruby product-crew-os-skill/tests/run-regression.rb --mock-delegate --check-only
ruby product-crew-os-skill/tests/run-external-benchmark.rb
ruby product-crew-os-skill/tests/run-routing-eval.rb
ruby product-crew-os-skill/tests/run-embedding-rag-dry-run.rb
ruby product-crew-os-skill/tests/run-rag-ingestion-contract.rb
ruby product-crew-os-skill/tests/run-runtime-smoke.rb
ruby product-crew-os-skill/tests/run-sop-e2e-smoke.rb
ruby product-crew-os-skill/tests/run-review-loop-e2e.rb
ruby product-crew-os-skill/tests/run-loop-50-cases.rb
```

通过标准：

- `validate-package: PASS`
- `run-regression: PASS`
- `run-external-benchmark: PASS`
- `run-routing-eval: PASS`
- `run-embedding-rag-dry-run: PASS`
- `run-rag-ingestion-contract: PASS`
- `run-runtime-smoke: PASS`
- `run-sop-e2e-smoke: PASS`
- `run-review-loop-e2e: PASS`
- `run-loop-50-cases: PASS`
- `run-routing-eval` 的 Stage accuracy、Skill hit rate、Agent recall 必须达到阈值。
- `run-embedding-rag-dry-run` 的 RAG hit@k、source trace rate、false positive domain entry rate 和 namespace isolation 必须达到阈值；它不代表真实外部 embedding provider 已上线。
- `run-rag-ingestion-contract` 必须证明 OCR、语义结构化 overlap chunk、开源 embedding、SQLite vector store、批处理、增量更新、维护和监控都有结构化配置与 schema 字段。
- `run-local-open-source-embedding-provider-contract` 只有在本机能真实加载 `BAAI/bge-small-zh-v1.5` 并返回向量时才通过；缺少 `sentence-transformers` / `FlagEmbedding` 或模型不可用时必须返回 `runtime_blocked_missing_local_model`。
- `run-review-loop-e2e` 必须证明用户未确认不能关闭评审，未解决 must-fix 不能关闭评审。
- `prompt-eval-cases.yaml` 至少包含 44 个 case。
- `manual-score-cases.yaml` 至少保留核心人工评分样本，用于判断人味、可追溯性和 Review Loop 质量。
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

人工评分样本沉淀在：

```text
tests/manual-score-cases.yaml
```

它不替代自动测试，主要用于评估：

- 主控教练是否真的判断 Stage，而不是顺着用户随口回答。
- 子 Agent 是否绑定用户配置的角色名、职责和记忆，而不是环境随机昵称。
- Review Loop 是否把完整评审原文、修改点、冲突点、用户决策和再评审记录下来。
- 产品体验是否像“有温度的 AI 产品办公室”，而不是一组裸工具命令。

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
- 至少 1 组 loop 50 case，用来锁定近期高风险 Bad Case：非产品退出、角色名绑定、raw review、团队风格授权、项目资产包导出、用户决策闭环。

## 6. 50 个 Loop 测试

`run-loop-50-cases.rb` 是当前发布前的综合 loop runner。它不是单纯检查文件存在，而是把 44 个 SOP prompt case 逐条写入 runtime，并额外验证 6 个高风险 Bad Case。

它默认启用本地 SQLite 测试账本：

```text
tests/results/product-crew-os-test-ledger.sqlite3
```

如果 case 上次已通过，且输入、runner、runtime、schema、README、结构化评审规则和团队风格授权规则等指纹没有变化，本轮会标记为 `SKIP_PASS`，不重复执行。

执行命令：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb
```

发布门禁强制全量重跑：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb --release-gate
```

输出位置：

普通增量报告写入 `tests/results/loop-50-cases-latest.md`；发布门禁全量报告写入 `tests/results/loop-50-cases-latest-force.md`。

可提交档案：

```text
tests/badcase-loop-50.md
```

通过标准：

- 50/50 case 通过。
- 日常增量测试允许已通过且指纹未变化的 case 标记为 `SKIP_PASS`。
- 发布门禁不允许 `SKIP_PASS`，必须 50 个 case 本次实际执行并通过。
- 44 个 SOP 都能产生 artifact、review session、context packet、invocation ledger 和 raw review record。
- 已知 Bad Case 不复发。
- 如果出现失败，必须修正规则或代码后重新运行，不能只修改报告。

## 7. 团队记忆测试

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

## 8. 第三方 Benchmark 接入

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

## 9. 后续自动化方向

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
