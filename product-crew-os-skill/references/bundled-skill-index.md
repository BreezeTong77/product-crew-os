# Bundled Skill Index

本文件是 Skill Router 的内置能力索引。主控教练在执行 `skill-stage-router.md` 时，应优先查找这里列出的内置实现，再考虑用户自有 skill overlay。

## 调用规则

1. Router 选中某个能力名后，先在本文件查找同名内置实现。
2. 若存在内置实现，读取对应 `third_party/skills/<folder>/SKILL.md` 作为能力说明，并按其 references/scripts/templates 执行。
3. 若用户配置了同名或更贴合的自有 skill overlay，用户 overlay 优先，但仍保留 Product Crew OS 的 SOP、子 Agent、Artifact 和 Stage Gate。
4. 若能力属于 MCP/插件适配器，先确认用户授权和工具可用，不能把未授权外部工具说成已调用。
5. 第三方 skill 的作者、来源和许可证边界见 `../THIRD_PARTY_NOTICES.md`；Product Crew OS 自有规则不覆盖第三方许可证。

## 内置映射

| Router Skill | 内置目录 | License 状态 | 作者/来源状态 |
| --- | --- | --- | --- |
| `assumption-mapper` | `third_party/skills/pratik-assumption-mapper` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `bmad-business-analyst` | `third_party/skills/bmad-business-analyst` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `code-to-prd` | `third_party/skills/alirez-code-to-prd` | MIT | Alireza Rezvani / https://github.com/lihanglogan/code-to-prd |
| `define-jtbd-canvas` | `third_party/skills/pop-define-jtbd-canvas` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `define-opportunity-tree` | `third_party/skills/pop-define-opportunity-tree` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `define-prioritization-framework` | `third_party/skills/pop-define-prioritization-framework` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `define-problem-statement` | `third_party/skills/pop-define-problem-statement` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `deliver-acceptance-criteria` | `third_party/skills/pop-deliver-acceptance-criteria` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `deliver-prd` | `third_party/skills/pop-deliver-prd` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `deliver-user-stories` | `third_party/skills/pop-deliver-user-stories` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `experiment-design` | `third_party/skills/assimovt-experiment-design` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `experiment-design` | `third_party/skills/pratik-experiment-design` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `feature-investment-advisor` | `third_party/skills/dean-feature-investment-advisor` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `jobs-to-be-done` | `third_party/skills/dean-jobs-to-be-done` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `jtbd-analysis` | `third_party/skills/assimovt-jtbd-analysis` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `measure-dashboard-requirements` | `third_party/skills/pop-measure-dashboard-requirements` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `metric-dashboard` | `third_party/skills/aroy-metric-dashboard` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `metrics-framework` | `third_party/skills/assimovt-metrics-framework` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `north-star-metric` | `third_party/skills/phuryn-north-star-metric` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `opportunity-solution-tree` | `third_party/skills/phuryn-opportunity-solution-tree` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `pencil-design` | `third_party/skills/pencil-design` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `pm-workbench` | `third_party/skills/pm-workbench` | MIT License | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `prd-critic` | `third_party/skills/pratik-prd-critic` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `prd-development` | `third_party/skills/dean-prd-development` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `prd-taskmaster` | `third_party/skills/prd-taskmaster` | MIT License | 保留原始 skill 内容 / https://github.com/anombyte93/prd-taskmaster |
| `prd-writing` | `third_party/skills/assimovt-prd-writing` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `prioritization-advisor` | `third_party/skills/dean-prioritization-advisor` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `problem-clarity` | `third_party/skills/pratik-problem-clarity` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `problem-statement` | `third_party/skills/dean-problem-statement` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `product-analytics` | `third_party/skills/alirez-product-analytics` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `product-discovery` | `third_party/skills/alirez-product-discovery` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `product-manager-interrogation` | `third_party/skills/skill-product-manager` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `product-manager-skills` | `third_party/skills/product-manager-skills-digidai` | CC-BY-NC-SA-4.0 | Gene Dai <gene@genedai.me> (https://genedai.me/) / https://github.com/Digidai/product-manager-skills.git |
| `product-strategy` | `third_party/skills/aroy-product-strategy` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `product-strategy` | `third_party/skills/phuryn-product-strategy` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `research-synthesis` | `third_party/skills/assimovt-research-synthesis` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `roadmap-planning` | `third_party/skills/assimovt-roadmap-planning` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `roadmap-planning` | `third_party/skills/dean-roadmap-planning` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `scope-cutting` | `third_party/skills/assimovt-scope-cutting` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `shape-up` | `third_party/skills/turner-shape-up` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `stakeholder-alignment-checker` | `third_party/skills/pratik-stakeholder-alignment-checker` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `strategy-doc` | `third_party/skills/assimovt-strategy-doc` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/assimovt/productskills |
| `summarize-interview` | `third_party/skills/phuryn-summarize-interview` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `test-scenarios` | `third_party/skills/phuryn-test-scenarios` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `trustworthy-experiments` | `third_party/skills/turner-trustworthy-experiments` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `user-research-synthesis` | `third_party/skills/aroy-user-research-synthesis` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |
| `user-story-mapping` | `third_party/skills/dean-user-story-mapping` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / https://github.com/deanpeters/product-manager-prompts |
| `utility-pm-critic` | `third_party/skills/pop-utility-pm-critic` | Apache-2.0 | 保留原始 skill 内容 / https://github.com/product-on-purpose/pm-skills |
| `value-vs-effort` | `third_party/skills/pratik-value-vs-effort` | 按随附文件或上游声明使用 | 保留原始 skill 内容 / 按随附文件或上游仓库声明 |

## Template / Adapter Fallback

这些能力由 Product Crew OS 模板、用户自有 skill 或授权插件/MCP 兜底，不影响 49 个内置 PM skill 的开箱使用：

- `deliver-launch-checklist`
- `develop-design-rationale`
- `figma:figma-generate-diagram`
- `figma:figma-use`
- `measure-instrumentation-spec`
