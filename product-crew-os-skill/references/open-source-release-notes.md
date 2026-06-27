# Open Source Release Notes

Use this file when preparing Product Crew OS for GitHub.

## Publish as a Skill, Not as User Memory

Commit:

- `SKILL.md`
- `agents/openai.yaml`
- `config/*.yaml` default templates
- `references/*.md`
- `templates/*.json`
- example transcripts using fake projects
- regression scenario files

Do not commit:

- `memory/`
- real PRDs
- customer interviews
- company metrics
- personal preferences
- generated project checkpoints
- tool-call logs

## Recommended `.gitignore`

```gitignore
memory/
*.local.yaml
*.overlay.yaml
.checkpoints/
tests/results/
work/
```

## README Must Explain

- what this is: a Codex skill / AI PM workflow orchestrator
- what this is not: not a full CrewAI Python project and not a replacement for real stakeholder approval
- how to install or copy the skill folder
- how to trigger `$product-crew-os`
- how the workflow SOP library maps product stages to inputs, outputs, stakeholders, and gates
- how real sub-agent invocation differs from simulated role perspective
- how to customize personas safely
- why `role_key` should stay stable
- how external PM skills are optional capabilities with fallbacks
- how to avoid committing private memory
- experimental version and schema version

## Versioning

Use both:

- `schema_version` in config files
- Git release tags for package changes

Suggested early tags:

- `v0.1.0`: skill prototype
- `v0.2.0`: evolution/checkpoint policy
- `v0.3.0`: examples and regression scenarios
