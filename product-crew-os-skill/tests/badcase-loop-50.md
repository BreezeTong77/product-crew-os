# 50 个 Loop 测试与 Bad Case 档案

本文件记录 Product Crew OS 的 50 个 loop 测试来源、验证目标和近期 Bad Case 修正点。它是可提交的测试档案；每次真实运行产生的详细报告写入 `tests/results/loop-50-cases-latest.md`，该目录默认不进入公开发布包。

增量测试状态写入本地 SQLite 测试账本：

```text
tests/results/product-crew-os-test-ledger.sqlite3
```

已通过且指纹未变化的 case 后续会标记为 `SKIP_PASS`，不重复执行。账本 schema 和使用说明见 `test-ledger-schema.sql` 与 `test-ledger.md`。

## 测试方法

每个 case 都按以下闭环执行：

```text
用户输入
-> 预期 Stage / SOP / Skill / Agent / Artifact / Gate
-> Runtime 写入 SQLite
-> 断言数据库、项目资产包、raw review 和角色绑定
-> 记录证据
-> 失败项进入 Bad Case
-> 修正规则或代码
-> 重新运行
```

## 覆盖范围

| 范围 | 数量 | 说明 |
| --- | ---: | --- |
| 44 个标准 SOP | 44 | 来自 `prompt-eval-cases.yaml`，覆盖完整 PM 工作流 |
| 负例路由 | 1 | 非产品任务不能强行进入 Product Crew OS |
| 子 Agent 身份绑定 | 1 | 运行时昵称不能覆盖用户配置角色名 |
| raw review 可见性 | 1 | 主控摘要不能替代角色原始评审记录 |
| 团队风格授权 | 1 | 真实同事材料必须授权后才能反哺记忆 |
| 项目资产包导出 | 1 | 产物、决策、评审和记忆必须进入可读项目包 |
| 用户决策闭环 | 1 | 主控不能替用户采纳、拒绝或关闭评审 |

## 已锁定 Bad Case

| Case | 问题 | 修正方式 | 回归文件 |
| --- | --- | --- | --- |
| L45 | 非产品问题被强行套入 SOP | README / SOP 明确 Domain Gate，非产品任务退出 Product Crew OS | `run-loop-50-cases.rb` |
| L46 | 真实运行时昵称污染产品角色名，例如 Faraday 覆盖张工 | `agent_invocations` 分离 `role_title`、`display_name`、`runtime_nickname` | `run-runtime-smoke.rb` / `run-loop-50-cases.rb` |
| L47 | 主控只给摘要，用户看不到子 Agent 原始评审 | `raw-review-records/<role_key>.md` 保留完整原文和审计字段 | `run-sop-e2e-smoke.rb` / `run-loop-50-cases.rb` |
| L48 | 用户提供的同事邮件、会议截图可能被误写入长期团队风格 | 团队风格反哺必须有授权、用途和存储范围 | `run-loop-50-cases.rb` |
| L49 | 项目资料只停留在聊天框，不能回溯 | Project Asset Pack 导出 Markdown / Obsidian-compatible 项目包 | `run-runtime-smoke.rb` / `run-loop-50-cases.rb` |
| L50 | 主控替用户采纳、拒绝或结束评审 | Structured Review Loop 明确展示全记录，由用户决定采纳、拒绝、暂缓、补证据或退出评审 | `structured-review-loop.md` / `run-loop-50-cases.rb` |

## 运行命令

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb
```

发布前强制全量重跑：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb --force
```

预期输出：

```text
run-loop-50-cases: PASS
cases: 50
```

## 后续扩展

- 将 50 个 case 分成 P0 / P1 / P2，用于不同发布阶段。
- 增加多轮用户纠错样本，验证意图识别、复评和 Stage 回退。
- 在 Coze / Dify / LangGraph / 自研 Web App 适配时，把 L46 和 L47 作为宿主验收项，确保真实子 Bot 和产品角色不会混淆。
