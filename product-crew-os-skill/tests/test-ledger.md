# 测试用例与 Bad Case 数据库

Product Crew OS 使用本地 SQLite 测试账本记录测试用例、执行结果和 Bad Case 修复状态。它解决两个问题：

1. 已经通过且相关文件没有变化的测试用例，后续默认跳过，不重复消耗时间。
2. Bad Case 不只停留在聊天记录里，而是进入可查询的数据库和回归测试。

## 默认数据库位置

```text
product-crew-os-skill/tests/results/product-crew-os-test-ledger.sqlite3
```

`tests/results/` 是本地运行产物，默认不提交到 Git。公开仓库提交的是 schema、runner 和 Bad Case 档案；每个用户或宿主环境会生成自己的本地测试账本。

## 数据表

| 表 | 作用 |
| --- | --- |
| `test_cases` | 每个测试用例的最新状态、指纹、通过次数、失败次数和跳过次数 |
| `test_case_runs` | 每次执行或跳过的流水记录 |
| `badcases` | Bad Case 标题、症状、修复方式、回归文件和状态 |

Schema 文件：

```text
product-crew-os-skill/tests/test-ledger-schema.sql
```

## 增量测试

默认命令会启用测试账本：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb
```

如果某个 case 上次已经 `PASS`，且 case 输入、runner、runtime、schema、README、结构化评审规则、团队风格授权规则等指纹都没有变化，本轮会显示：

```text
SKIP_PASS
```

这表示该 case 已由历史 PASS 记录和当前指纹共同确认，不再重复执行。

## 强制全量重跑

发布前或大改 runtime 后，可以强制重跑全部 50 个 case：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb --force
```

## 自定义账本位置

如果宿主平台或 CI 想保存自己的测试数据库：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb --ledger-db /path/to/product-crew-os-test-ledger.sqlite3
```

## 关闭账本

如果只想临时跑一次，不记录状态：

```bash
ruby product-crew-os-skill/tests/run-loop-50-cases.rb --no-ledger
```

## 未来扩展

- 将 44 个 SOP case 和 6 个 Bad Case 分成 P0 / P1 / P2。
- 增加多轮用户纠错样本。
- 在 Coze / Dify / LangGraph / 自研 Web App 中把同一 schema 迁移为平台数据库表。
- 接入更多字段：模型版本、子 Agent 运行环境、token 消耗、失败堆栈、修复 owner、复测时间。
