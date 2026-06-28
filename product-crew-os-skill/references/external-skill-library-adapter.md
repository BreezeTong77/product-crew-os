# 第三方 PM 能力包适配规则

Product Crew OS 可以评估、内置或接入第三方 PM skill 包、团队内部模板或外部能力库，但不能让外部能力包替代产品本体。

## 1. 正确关系

```text
Product Crew OS = 主控教练 + workflow + review + artifact workspace
第三方 PM 能力包 = 可内置或可选覆盖的能力来源
```

外部 skill 可以补强能力，但不能替代：

- 主控教练的阶段判断。
- stakeholder review。
- Artifact Workspace。
- 记忆边界。
- 用户授权和隐私规则。

## 2. 适配流程

评估一个第三方能力包时，按以下步骤：

1. 读取 README、目录结构、LICENSE 和安装方式。
2. 识别它的能力分组、命令入口、skill 数量和工作流数量。
3. 把每个能力映射到 Product Crew OS 的阶段。
4. 判断它是补充、替代、冲突，还是暂不建议。
5. 检查语言、维护状态、权限风险和外部写入能力。
6. 向用户说明推荐原因和风险。
7. 若只是当前用户/项目使用，写入 User Preference Memory 或 Project Workspace overlay。
8. 若要成为默认能力，复制到 `third_party/skills/`，并补齐原作者、来源、许可证和风险说明。

## 3. 映射字段

每个外部 skill 至少记录：

```yaml
name:
source:
license:
language:
stage_fit:
input:
output:
replaces:
complements:
risks:
requires_external_write:
install_scope: user | project
enabled: false
```

## 4. 不要无声明吞并

禁止：

- 未经评估、未保留许可证和作者声明，就把外部几十个 skill 写入公共规则包。
- 未经用户确认自动安装。
- 把外部 skill 的具体示例、业务项目或作者表达混写进 Product Crew OS 自有公共规则。
- 让用户必须记住大量命令才能使用 Product Crew OS。

允许：

- 在月度 skill 发现中推荐外部 skill。
- 将经过验证且许可证允许的第三方 skill 内置到 `third_party/skills/`，并在 `THIRD_PARTY_NOTICES.md` 中标注原作者和许可证。
- 把经过验证的外部 skill 映射为某阶段的首选或 fallback。
- 为高级用户提供可见能力面板。
- 为新手用户隐藏具体 skill 名，继续由主控教练自然语言引导。

## 5. 可吸收的设计原则

可吸收：

- 清晰的能力地图。
- 命令式快速入口。
- 能力 / 流程 / 产物的层级表达。
- 每个任务完成后推荐下一步。
- 跨工具的可迁移安装说明。

不可牺牲：

- 把产品体验变成 skill 菜单。
- 取消主控教练判断。
- 取消 stakeholder review。
- 把项目记忆、用户偏好和产品规则混放。
