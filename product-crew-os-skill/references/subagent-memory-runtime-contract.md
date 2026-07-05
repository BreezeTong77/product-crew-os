# Sub-Agent Memory Runtime Contract

本文件定义 Product Crew OS 的子 Agent 长期记忆与反哺机制。

先说清楚边界：

```text
子 Agent 聊天窗口本身不拥有可靠长期记忆。
长期记忆由主控教练在 Project Workspace / User Preference Memory 中管理。
每次召唤子 Agent 时，主控教练负责读取、压缩、注入和回写。
```

也就是说，`文设计`、`张工`、`李测` 等角色不是靠底层子代理工具自己记住历史，而是靠主控教练把角色记忆注入本轮 context packet。

## 1. 记忆来源

每次召唤子 Agent 前，主控教练必须按顺序读取以下材料：

| 层级 | 路径 / 来源 | 用途 |
| --- | --- | --- |
| Base Persona | `config/crew-personas.yaml` | 角色默认名称、人格、职责、说话风格 |
| User Overlay | `memory/users/{user_id}/crew-overlay.yaml` | 用户自定义角色名称、语气、严格度 |
| User Team Style | `memory/users/{user_id}/team-style-overlay.yaml` | 用户长期偏好的团队风格 |
| Project State | `memory/projects/{project_id}/project-state.json` | 当前阶段、artifact、风险、决策 |
| Project Role Memory | `memory/projects/{project_id}/agent-memory/{role_key}.md` | 该角色在当前项目中的历史关注点和上次卡点 |
| Project Team Style | `memory/projects/{project_id}/team-style-overlay.yaml` | 当前项目特有团队风格 |
| Decision Log | `memory/projects/{project_id}/decision-log.md` | 已采纳 / 拒绝 / 延后的决策 |
| Source Ledger | `memory/projects/{project_id}/source-ledger.md` | 证据来源和可信度 |

如果某个文件不存在，主控教练不能假装有记忆，只能把对应字段标记为 `empty` 或 `unknown`。

## 2. 召唤前注入规则

主控教练必须把读取到的记忆压缩成 `agent-context-packet.yaml` 中的 `memory_snapshot`。

推荐结构：

```yaml
memory_snapshot:
  base_persona:
    role_key: "Design"
    display_name: "文设计"
    stable_concerns: []
  user_overlay:
    exists: false
    summary: ""
  project_role_memory:
    exists: false
    last_objections: []
    recurring_concerns: []
    previously_blocked_gates: []
  team_style_overlay:
    exists: false
    tone_rules: []
    phrases_to_use: []
    phrases_to_avoid: []
  relevant_decisions: []
  relevant_open_risks: []
  evidence_boundary:
    confirmed: []
    inferred: []
    unknown: []
```

子 Agent 只能基于本轮 context packet 发言，不能声称自己记得未被注入的历史。

## 3. 召唤后反哺规则

子 Agent 返回后，主控教练必须把输出拆成四类：

| 类型 | 写入位置 | 示例 |
| --- | --- | --- |
| Artifact 修改 | 当前 artifact | PRD、原型 brief、测试场景 |
| Review Item | `review-items.yaml` | 需补充异常状态 |
| Decision Log | `decision-log.md` | 采纳 / 拒绝 / 延后某建议 |
| Memory Delta | `memory_delta_queue` | 该角色反复关注某风险 |

不是每条子 Agent 发言都能直接写入长期记忆。

### 3.1 外部材料怎么写入

用户上传的同事邮件截图、会议纪要、聊天导出、客服对话等都属于外部材料，不直接写进角色上下文窗口或 `agent-memory`。

执行顺序：

```text
1) 提取证据（OCR/转写）并去标识化
2) 生成来源摘要，写入 source-ledger（source_ref）
3) 若涉及当前 artifact 依据，更新 decision / review item / source mapping
4) 依据用户授权，决定是否写入
   - 项目知识层：`Project Workspace`（可追溯）
   - 角色风格层：`agent-memory/{role_key}.md`（仅偏好与风格摘要）
```

这样既保留了可追溯链条，也避免把原文“原样”长期记忆化。

长期记忆写入必须满足：

- 有来源：来自哪次评审、哪个 artifact、哪个 role_key。
- 有范围：本轮、当前项目、用户偏好、产品规则。
- 有置信度：confirmed / inferred / assumption。
- 有用户授权：涉及真实团队材料、同事语气、公司内部表达时必须询问。

## 4. 压缩规则

当出现以下情况时，主控教练应压缩上下文：

- 评审会结束。
- artifact 创建或修改完成。
- 子 Agent 提出阻塞意见。
- 用户明确说“保存”“记一下”。
- 项目阶段切换。
- 当前上下文过长，旧讨论开始干扰下一步。

压缩后必须保留：

- 当前阶段。
- 当前 artifact 和版本。
- 已采纳决策。
- 未解决问题。
- 阻塞角色和阻塞原因。
- 每个角色最新的关键反对意见。
- 下一步动作。
- 来源和证据边界。

压缩后不得保留：

- 未经授权的真实团队原文。
- 未脱敏客户、公司、项目名称。
- 临时模拟内容。
- 推断成事实的内容。

## 5. 角色记忆文件格式

`memory/projects/{project_id}/agent-memory/{role_key}.md` 推荐格式：

```md
# Agent Memory: Design

## 角色配置

- role_key:
- display_name:
- 当前项目语气 overlay:

## 长期关注点

- 

## 最近一次评审

- artifact:
- stage:
- conclusion:
- blockers:
- accepted_suggestions:
- rejected_suggestions:

## 反复出现的问题

- 

## 下次召唤前必须提醒

- 

## 来源

- 
```

## 6. 反哺到团队风格

真实同事回复、邮件、会议纪要、评审意见可以反哺角色风格，但必须先问用户：

```text
这段材料你希望我怎么用？
1. 只用于本轮判断，不保存
2. 作为当前项目上下文
3. 作为某个角色的风格样本
4. 同时作为项目上下文和角色风格样本
```

只有用户授权后，才能提取：

- 语气。
- 关注点。
- 常见卡点。
- 偏好表达。
- 禁用表达。
- 评审严格度。

禁止提取或保存：

- 真实同事身份仿冒。
- 未脱敏原文。
- 个人隐私。
- 公司敏感信息。
- 可以反推出真实客户或项目的信息。

## 7. 运行时验收标准

一次合格的“带记忆子 Agent 调用”必须满足：

1. 读取 base persona。
2. 检查 user overlay 和 project overlay。
3. 检查 `agent-memory/{role_key}.md` 是否存在。
4. 将压缩后的记忆写入 `memory_snapshot`。
5. 子 Agent 发言只能引用 context packet 中存在的信息。
6. 召唤后生成 memory delta。
7. 有授权才写入长期用户偏好或团队风格。
8. 写入项目记忆前必须标注来源、范围和置信度。
9. 如果没有历史记忆，必须明确为“本项目暂无该角色历史记忆”。

## 8. 用户可见说明

当用户打开底层子 Agent 聊天，发现它没有过往记忆，主控教练应解释：

```text
这是正常的。底层子 Agent 不是长期记忆容器。
Product Crew OS 的长期记忆保存在 Project Workspace 中。
每次召唤时，我会把该角色需要知道的压缩记忆注入 context packet。
```

禁止说：

```text
它自己会记得。
```

除非运行时真的提供独立持久化 Agent Memory，并且 Product Crew OS 已经完成对接。
