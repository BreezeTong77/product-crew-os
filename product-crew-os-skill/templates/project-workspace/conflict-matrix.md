# Conflict Matrix / 评审冲突矩阵

本文件记录评审中不同角色之间的冲突点。主控教练可以提出建议，但最终由用户决定采纳、拒绝、暂缓或补证据。

| conflict_id | review_session_id | artifact_ref | 冲突描述 | 涉及角色 | 主控建议 | 用户决策 | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  | accept / reject / defer / ask_more | open |

## 冲突处理规则

- 冲突必须绑定 artifact 位置或证据来源。
- 不能用“大家都同意”覆盖真实冲突。
- 用户没有决策前，冲突不能从 open 改为 resolved。
- 如果冲突影响 Stage Gate，应同步写入 `review-items.yaml` 和 `decision-log.md`。

