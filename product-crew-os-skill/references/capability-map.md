# Product Crew OS 能力地图

本文件用于向用户解释 Product Crew OS 能覆盖哪些产品工作，而不是要求用户手动选择 skill。

核心原则：

```text
用户说目标 -> 主控教练判断阶段 -> 选择能力 -> 生成 artifact -> 必要时评审 -> 推进下一步
```

## 1. 能力分组

| 分组 | 典型用户表达 | 内部阶段 | 主要产物 |
| --- | --- | --- | --- |
| 项目接入 | 我有个想法 / 我想做个产品 | project_intake, request_triage | project card, next-step plan |
| 商业与战略判断 | 值不值得做 / 商业模式怎么看 | business_context, value_sizing, prioritization | business note, value sizing, priority stack |
| 需求发现与验证 | 这是真需求吗 / 怎么调研 | evidence_inventory, problem_definition, research_plan | evidence inventory, problem statement, research plan |
| 用户理解 | 用户是谁 / 他们到底想完成什么 | user_segmentation, JTBD, journey | segment note, JTBD, journey map |
| 方案设计 | 方案怎么落地 / 给我几个方案 | solution_exploration, mvp_scope, one_page_proposal | solution options, MVP scope, proposal |
| 流程与原型 | 画流程 / 做 demo / 做原型 | core_flow_diagram, low_fi_prototype | flow brief, low-fi prototype brief, HTML demo brief |
| 数据与指标 | 指标怎么算 / 埋点怎么做 | metrics_design, instrumentation_plan | metrics tree, event spec |
| PRD 与评审 | 写 PRD / 帮我内审 / 正式评审 | prd_outline, prd_v0_draft, review stages | PRD, review notes, decision log |
| 交付拆解 | 拆任务 / 怎么验收 / 怎么排期 | task_breakdown, acceptance_criteria | epic/story/task, acceptance criteria, test scenarios |
| 上线与运营 | 准备上线 / 怎么培训 / 怎么试点 | launch_readiness, training, grey_release_pilot | launch checklist, SOP, pilot plan |
| 复盘与迭代 | 上线后看什么 / 做复盘 | launch_monitoring, post_launch_review, iteration_planning | monitoring notes, postmortem, iteration backlog |

## 2. SOP 覆盖规则

能力地图只是用户看得懂的入口，真正执行时必须落到细分 SOP。

主控教练每次推进一个实质流程时，应检查 `workflow-sop-library.md`：

- 当前 stage 需要什么输入。
- 标准推进动作是什么。
- 输出哪个 artifact。
- 默认或条件召唤哪些干系人。
- 什么条件算过关。

如果用户自带公司 SOP、模板或 skill，可以作为 overlay 替换默认 SOP，但不能取消输入、输出、干系人和过关标准。

## 3. 能力呈现规则

普通用户看到的是“我正在帮你做什么”，不是 skill 名称清单。

示例：

- 我现在会先帮你做真伪需求判断。
- 这一步需要商业价值评估和用户证据盘点。
- 这个原型阶段我建议先出 image 概念图，再做 HTML Demo。
- 这版 PRD 还没到正式评审，我先做产品自审。

高阶用户可以打开能力面板，看到：

- 内置能力。
- 用户自带能力。
- 当前阶段适配度。
- 首选 skill。
- fallback skill。
- artifact 模板。
- 是否需要外部工具或 MCP。

## 4. 不做技能菜单化

Product Crew OS 可以借鉴优秀能力库的清晰结构表达，但不能退化成“几十个 skill 按钮”。

主控教练必须保留判断责任：

- 用户不知道该用哪个能力时，主控教练主动判断。
- 用户直接点名某个能力时，主控教练仍要检查阶段是否合适。
- skill 输出必须进入 Artifact Workspace，而不是停留在聊天回答。
- 每个阶段结束时，主控教练要提醒下一步产物和需要对齐的人。
