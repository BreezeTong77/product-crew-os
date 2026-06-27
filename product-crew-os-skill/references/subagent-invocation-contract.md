# Sub-Agent Invocation Contract

本文件定义 Product Crew OS 如何把用户设定的角色绑定到真实子 Agent 调用。

核心原则：

```text
role_key 是稳定身份
persona 是用户可配置的人格
context packet 是本轮评审上下文
agent invocation 是真实调用记录
```

没有真实调用记录时，主控教练不能说“已拉起子 Agent”。

## 1. 绑定模型

子 Agent 绑定不是靠聊天文本里的名字，而是靠四层绑定：

| 层级 | 来源 | 作用 |
| --- | --- | --- |
| `role_key` | `crew-personas.yaml` / `stakeholder-boundaries.yaml` | 稳定机器身份，例如 `Design`、`Tech`、`QA` |
| persona | `crew-personas.yaml` + 用户或项目 overlay | 显示名、角色名称、性格、语气、关注点 |
| boundary | `stakeholder-boundaries.yaml` / `stage-boundary-matrix.md` | 决定该角色在当前 stage 是否允许出现 |
| context packet | `templates/agent-context-packet.yaml` | 本轮评审的问题、产物、证据、风险、边界 |

用户可以修改显示名、性格、语气和评审严格度，但默认不改 `role_key`。`role_key` 一旦乱改，历史记忆、评审记录和阶段边界会失去可追溯性。

## 2. 真实调用规则

当运行环境提供真实子代理、delegate、worker、reviewer 或类似能力时，主控教练必须遵守：

1. 如果 SOP、stage boundary、用户指令或主控判断表明需要某个角色评审，必须真实调用子代理。
2. 调用前必须构造 context packet。
3. 调用提示词必须写明 `role_key`、角色名称、显示名、人格/语气摘要、当前 stage、artifact、review question、role scope 和 gate。
4. 调用返回后，主控教练必须把结果收束成 artifact 修改、review item、decision log 或 next action。
5. 本轮完成后必须记录 invocation ledger。

如果运行环境没有真实子代理能力，或本轮无法调用，主控教练只能说：

```text
下面是模拟 <角色显示名> 视角，不是已真实拉起子 Agent。
```

禁止用“已拉起”“已召唤”“团队成员说”这类说法包装模拟文本。

## 3. 即时召唤规则

SOP 和边界矩阵是最低要求，不是唯一来源。

即使 SOP 没有显式写必须召唤某个角色，只要主控教练判断满足以下任一条件，就应即时真实调用对应角色：

- 当前产物会影响该角色负责的风险面。
- 用户明确要求该角色视角、团队评审、反驳或把关。
- 当前 gate 可能因为该角色领域问题被阻塞。
- 用户指出主控教练可能误判或遗漏该角色。
- 该角色的项目记忆或团队风格 overlay 会改变判断。

即时召唤时必须说明：

- 为什么 SOP 外仍然需要这个角色。
- 该角色评审什么。
- 该角色不替谁做决定。

## 4. Invocation Ledger

每次真实子 Agent 调用都应记录：

| 字段 | 含义 |
| --- | --- |
| `invocation_id` | 本轮调用 ID |
| `runtime_agent_id` | 真实工具返回的 agent id，如有 |
| `runtime_nickname` | 工具内部昵称，仅用于审计，不作为产品角色名 |
| `role_key` | 稳定角色身份 |
| `role_title` | 角色名称 |
| `display_name` | 用户看到的角色显示名 |
| `stage_id` | 当前阶段 |
| `artifact_id` | 被评审产物 |
| `context_packet_ref` | 本轮 context packet 引用 |
| `trigger_reason` | SOP、stage boundary、用户要求或主控即时判断 |
| `result` | pass / conditional_pass / block / advice_only |
| `timestamp` | 记录时间 |

工具内部昵称不能覆盖用户配置的角色名。比如真实工具返回昵称 `Maxwell`，但本轮 role_key 是 `Design`，用户看到的仍然是 `文设计`。

## 5. 验收标准

一次合格的子 Agent 召唤必须满足：

- 有明确 `role_key`。
- 有 persona 来源。
- 有 context packet。
- 有真实调用记录，或明确标注为模拟视角。
- 发言绑定 artifact 具体内容。
- 发言不越权。
- 主控教练收束为 artifact、review item、decision 或 next action。

任何时候，如果主控教练把模拟视角说成真实调用，应记录为 routing / invocation error，并更新规则或测试场景。
