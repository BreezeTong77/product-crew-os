# GitHub 发布检查清单 v0

日期：2026-07-05

发布目标：`v0.1.2`

## 1. 备份

- [x] 备份当前 Product Crew OS 自分析 workspace。
- [x] 创建独立 GitHub 发布暂存目录。
- [x] 确保项目记忆不进入发布包。

本地备份路径：

```text
<local-backup-path-outside-this-repository>
```

发布暂存路径：

```text
<local-release-staging-path>
```

## 2. 发布包结构

- [x] `README.md`
- [x] `LICENSE`
- [x] `CHANGELOG.md`
- [x] `.gitignore`
- [x] `github-release-checklist-v0.md`
- [x] `releases/v0.1.2.md`
- [x] `releases/v0.1.1.md`
- [x] `docs/product-rules.md`
- [x] `docs/portability-manifest.md`
- [x] `product-crew-os-skill/`

## 3. 隐私边界

不得包含：

- [x] 项目 workspace。
- [x] 用户偏好记忆。
- [x] 真实 PRD。
- [x] 客户访谈。
- [x] 会议转录。
- [x] 公司指标。
- [x] API key、token 或本地日志。
- [x] 临时模拟项目细节。

## 4. 公共发布内容

可以包含：

- [x] Product Rule Memory。
- [x] 通用 workflow 规则。
- [x] 细颗粒 Workflow SOP 库。
- [x] 阶段分类。
- [x] Stakeholder 边界。
- [x] 子 Agent 真实调用契约。
- [x] 子 Agent 长期记忆 runtime 契约。
- [x] `memory_snapshot` 注入规则。
- [x] 召唤后 memory delta 规则。
- [x] 模拟视角必须显式标注。
- [x] 子 Agent 调用记录 ledger。
- [x] 默认主控教练 profile：`甜心教练-董董`。
- [x] 主控教练名称、性格、语气和推进力度保持可配置。
- [x] 可配置的子 Agent 团队性格规则。
- [x] Artifact 模板。
- [x] Skill 路由参考。
- [x] 半透明 skill 可感知规则。
- [x] 用户自有 skill 和月度 skill 发现规则。
- [x] 能力地图。
- [x] 三种使用模式和自然语言触发语。
- [x] 第三方 PM 能力包适配规则。
- [x] 内置第三方 PM skill pack。
- [x] 第三方作者、来源和许可证声明。
- [x] Semantic Stage Router。
- [x] Stage -> SOP -> Skill -> Stakeholder -> Artifact -> Stage Gate 闭环。
- [x] MCP 可选适配规则。
- [x] MCP 显性授权规则。
- [x] Deep Artifact Pack 最小模板。
- [x] 低保真原型最小模板。
- [x] 原型增强路径：image 概念图 -> HTML Demo -> Pencil / Figma 可编辑原型。
- [x] 技术任务拆解最小模板。
- [x] 测试场景最小模板。
- [x] 回归测试场景。
- [x] 仅使用合成、通用示例。

## 5. 命名清理

- [x] 移除旧测试主控教练名称。
- [x] 移除用户特定称呼示例。
- [x] 使用可配置的默认主控教练 profile。
- [x] 角色名称保持可配置。
- [x] 子 Agent 性格和真实团队风格 overlay 只保存在用户或项目范围。

## 6. 发布前审计

执行：

```text
ruby product-crew-os-skill/tests/validate-package.rb
ruby product-crew-os-skill/tests/run-regression.rb --mock-delegate --check-only
rg -n "<private-user-name>|<private-coach-name>|<customer-name>|<secret-patterns>" .
```

预期结果：

```text
validate-package: PASS
run-regression: PASS
没有匹配到私有或用户特定材料。
```

同时检查：

```text
find . -maxdepth 3 -type f | sort
```

## 7. 建议 Git 命令

在发布暂存目录中执行：

```text
git add .
git commit -m "chore: release product crew os v0.1.2"
git branch -M main
git tag v0.1.2
```

然后创建 GitHub 仓库并推送：

```text
git remote add origin <your-repo-url>
git push -u origin main
git push origin v0.1.2
```

## 8. 发布后

- [ ] 使用 `releases/v0.1.2.md` 创建 GitHub Release。
- [ ] 后续工作放在 `next` 或 `dev` 分支。
- [ ] 每次有意义的改动都更新 `CHANGELOG.md`。
- [ ] 当配置 schema 变化时补充迁移说明。
- [ ] 永远不要提交本地项目 workspace。
