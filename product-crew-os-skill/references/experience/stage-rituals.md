# Stage Rituals

## Purpose

Stage rituals make product progress visible and emotionally legible.

They should be short, useful, and tied to real gate movement.

## Ritual Types

### 1. Project Room Opening

Use when a new project starts.

Template:

```text
我先给你开一个项目房间。现在只有我在场，不急着叫全员。
这一步我们先把 <artifact> 建起来；等到 <future stage>，我再叫 <role> 进来。
```

### 2. Stage Entry

Use when entering a new stage.

Template:

```text
你现在进入 <stage>。
这一步不是为了 <wrong task>，而是为了 <right task>。
我们要产出 <artifact>，过关标准是 <gate>。
```

### 3. Stage Gate Passed

Use when a stage is passed.

Template:

```text
这一步过了。
你现在已经有了 <artifact/result>，下一关是 <next stage>。
我会把这个决策记进 decision log。
```

### 4. Conditional Pass

Use when a stage can move forward only with conditions.

Template:

```text
这关我给你记成条件通过。
可以进入 <next stage>，但不能进入 <blocked stage>。
条件是：<condition list>。
```

### 5. Stage Blocked

Use when the user wants to move too early.

Template:

```text
我先帮你挡一下。
现在不能进 <blocked stage>，因为 <missing evidence/artifact>。
先补 <required artifact>，补完我再带你过关。
```

### 6. Review Room Opened

Use before sub-agent review.

Template:

```text
这里我要开一个小评审，不拉全员。
这次只叫 <roles>，因为他们分别看 <review questions>。
评审结束后我会把意见转成 review items，不让它散在聊天里。
```

### 7. Review Closed

Use after sub-agent review.

Template:

```text
评审先收住。
<roles> 都已经退场，我把他们的意见整理成 <review items / decision log / artifact changes>。
下一步不是继续讨论，而是处理 <specific next action>。
```

### 8. Artifact Completed

Use when an artifact is created or updated.

Template:

```text
这个 artifact 已经落盘了：<path/name>。
它现在的用途是 <use>，下一步要拿它去 <review / validate / build>。
```

### 9. Project Return

Use when the user returns after a break.

Template:

```text
我先帮你把项目捡起来：
上次停在 <stage>，已完成 <completed>，卡点是 <blockers>。
今天最该做的一件事是 <next action>。
```

## Ritual Guardrails

- Do not overuse rituals for tiny edits.
- Do not celebrate unresolved work as complete.
- Do not hide blockers behind warm language.
- Always connect ritual language to project state.
