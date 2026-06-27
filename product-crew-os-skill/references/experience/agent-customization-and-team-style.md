# Agent Customization and Team-Style Overlay

## Purpose

Product Crew OS should let users shape the product crew into a familiar product office.

Users can keep the default fictional roles, customize them, or use opt-in materials from their real team to make agent tone and review behavior more realistic.

## What Users Can Customize

Users may customize:

- role title
- display name
- personality
- speaking style
- strictness
- preferred review depth
- role visibility
- stage participation boundaries
- examples of good and bad feedback
- company-specific vocabulary

Users can customize roles at first use, during a project, or after a review. The coach should periodically remind the user that personalities and review style are adjustable, especially when the user says a role feels unlike their real team.

Protected fields:

- `role_key`
- default authority red lines
- memory container boundaries
- explicit human approval requirements

## Default Reminder

When a user starts using Product Crew OS or creates a new project, the coach should remind them:

```text
默认团队我先给你配好了。你可以改角色名称、性格、说话风格，甚至把它调成你真实公司里那种评审风格。
以后如果你愿意，也可以把同事回复、邮件、会议转录、评审意见作为样本喂给某个角色，让它更像你真实工作环境里的那个人。但这些只会进入你的个人或项目配置，不会进入公共产品规则。
```

## Team-Style Overlay

A team-style overlay is a user- or project-specific file that adjusts how roles speak and what they tend to care about.

It must not replace Product Rule Memory.

Recommended files:

```text
memory/users/<user_id>/team-style-overlay.yaml
memory/projects/<project_id>/team-style-overlay.yaml
memory/projects/<project_id>/agent-memory/<role_key>.md
```

## Acceptable Source Materials

With user permission, the system may learn style from:

- user-provided prompt instructions
- colleague replies
- review comments
- meeting transcripts
- emails
- chat excerpts
- PRD review notes
- acceptance comments
- decision records

These materials can improve:

- role personality
- agent wording
- strictness
- common concerns
- role-specific patterns
- realistic objections
- company vocabulary

## Prohibited Use

Do not put real team materials into:

- public product rules
- reusable skill configs intended for release
- README examples
- generic tests
- Product Rule Memory

Do not infer sensitive facts beyond the provided source.

Do not imitate a real person in a way that claims to be that person. The agent may represent a role style, not impersonate a human identity.

## Consent Rule

Before using real team materials, the coach must ask for confirmation.

Suggested prompt:

```text
你可以把这段材料作为项目上下文，也可以授权我把它提炼成某个角色的风格样本。
如果作为风格样本，我只会提取说话习惯、关注点和常见卡点，不会把具体业务内容写进产品规则。
你希望怎么处理？
```

Options:

1. Project context only.
2. Role style sample.
3. Both project context and role style sample.
4. Do not store, only use this turn.

## Extraction Rules

When converting source materials into style memory, extract only:

- tone
- review style
- concern patterns
- preferred evidence
- typical objections
- vocabulary

Do not extract:

- confidential project facts
- customer names
- business data
- unreleased plans
- legal or HR-sensitive information
- private personal details

## Overlay Schema

Use `templates/overlays/team-style-overlay.yaml`.

Minimum fields:

- overlay owner
- scope
- source labels
- allowed roles
- tone rules
- role-specific style adjustments
- redactions
- expiration or review policy

## Review And Revert

Users should be able to:

- inspect current role settings
- reset to default personas
- disable a role overlay
- delete project-specific style memory
- export a sanitized style profile

Coach reminder:

```text
这个团队风格只是 overlay，可以随时关掉或恢复默认，不会改掉产品底层工作流。
```
