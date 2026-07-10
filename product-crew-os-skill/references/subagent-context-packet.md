# Sub-Agent Context Packet

Use this file before any sub-agent speaks.

The coach must not summon a sub-agent with only the raw chat history. Each sub-agent needs a compact, role-specific context packet. This is how Product Crew OS avoids shallow comments caused by context-window limits.

## Why This Exists

Sub-agent replies become vague when the agent does not know:

- the exact stage gate being reviewed
- which artifact and version is under review
- what the user has already decided
- what risks are still open
- which facts are confirmed versus inferred
- what the role is allowed to judge

The context packet gives every reviewer a small but high-signal brief.

## Required Packet Fields

Use `templates/agent-context-packet.yaml`.

Minimum fields:

- `stage_id`
- `artifact.name`
- `artifact.version`
- `artifact.summary`
- `review.role_key`
- `review.review_question`
- `review.role_scope`
- `memory_snapshot.base_persona.role_key`
- `memory_snapshot.base_persona.title`
- `memory_snapshot.base_persona.display_name`
- `memory_snapshot.base_persona.personality`
- `memory_snapshot.base_persona.speaking_style`
- `memory_snapshot.base_persona.must_do`
- `memory_snapshot.base_persona.must_not_do`
- `memory_snapshot.base_persona.memory_focus`
- `memory_snapshot.base_persona.persona_source_ref`
- `context.known_decisions`
- `context.open_risks`
- `evidence_boundary`
- `output_contract`

If these are missing, the coach must create them before the sub-agent speaks. A packet with only `role_key`, role title, and display name is not a valid Product Crew OS sub-agent context packet; it is only a named generic reviewer.

After the packet is prepared, apply `subagent-invocation-contract.md`.
The packet proves context quality; the invocation ledger proves whether a real sub-agent was actually called.

## Context Budget Rule

Use `config/review-depth-policy.yaml`.

- quick review: 2 snippets, 2 decisions, 2 risks
- standard review: 4 snippets, 4 decisions, 4 risks
- deep review: 8 snippets, 8 decisions, 8 risks

Do not dump the whole chat. Select only the details the role needs.

## Role-Specific Selection

### Tech

Include system boundary, APIs, data dependency, state flow, exception path, and implementation-related artifact sections.

### Data

Include metric definitions, source systems, fields, update frequency, attribution window, and missing-data handling.

### Design

Include user task, entry point, core flow, screen states, decision points, and user effort.

### CS

Include customer success context: rollout path, adoption friction, renewal risk, support burden, service promises, and training/support burden.

### Customer

Include external customer or boss-demand context: direct quotes, purchase/renewal pressure, acceptance promise, contract deadline, buyer objection, and what the customer believes they were promised.

### QA

Include acceptance criteria, state transitions, edge cases, rollback, and release blockers.

## Prompt Pattern

When summoning a sub-agent, the coach should internally frame it like:

> 你是 `<role title - name>`。只基于下面的 context packet 评审，不要补脑。请用自然语言给用户一个同事式反馈，同时保留 structured review shadow。

The prompt must include the stable `role_key`. If the runtime returns a system nickname, keep it only in the invocation ledger. Do not expose it as the user's configured role name.

The prompt must also include the configured persona block from `crew-personas.yaml` or an approved user/project overlay:

- personality
- speaking_style
- must_do
- must_not_do
- memory_focus

If the persona block is absent, mark the invocation as `context_packet_incomplete` and do not count it as a passed sub-agent invocation.

## No-Context Rule

If a sub-agent would have to say "看起来可能..." without evidence from the packet, it should say:

> 这里我不能确认。我先按假设提醒你，过关前需要补证据。

This keeps warmth without pretending certainty.
