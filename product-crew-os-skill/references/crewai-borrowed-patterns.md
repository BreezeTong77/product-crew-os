# CrewAI Patterns to Borrow

Product Crew OS should not copy CrewAI's user experience directly. This product is a PM coach, not a generic multi-agent framework. But several CrewAI production patterns are worth adapting.

Sources:

- CrewAI Agents: https://docs.crewai.com/en/concepts/agents
- CrewAI Crews: https://docs.crewai.com/en/concepts/crews
- CrewAI Flows: https://docs.crewai.com/en/concepts/flows
- CrewAI Memory: https://docs.crewai.com/en/concepts/memory
- CrewAI Tasks: https://docs.crewai.com/en/concepts/tasks
- CrewAI Production Architecture: https://docs.crewai.com/en/concepts/production-architecture
- CrewAI Checkpointing: https://docs.crewai.com/en/concepts/checkpointing
- CrewAI Testing: https://docs.crewai.com/en/concepts/testing

## 1. Flow-First Orchestration

CrewAI recommends starting production applications with Flows because Flows provide state, branching, conditionals, and observability.

Product Crew OS equivalent:

- The visible coach is the Flow controller.
- PM stages are Flow states.
- Skills and sub-agents are units of work triggered by the Flow.
- The stage boundary matrix is the routing layer.

## 2. Role, Goal, Backstory

CrewAI agents are shaped by role, goal, and backstory. Product Crew OS keeps the same separation with product-friendly fields:

- `role_key`: stable machine identity
- `title`: user-facing role
- `display_name`: customizable character name
- `role`: what the agent does
- `personality`: how the agent feels
- `speaking_style`: how the agent speaks
- `must_do` / `must_not_do`: hard behavior boundaries

## 3. Tasks with Expected Output

CrewAI tasks define expected outputs, tools, context, human input, and guardrails.

Product Crew OS should map each PM workflow step to a task contract:

- task name
- stage
- required artifact
- required input
- allowed agents
- allowed skills/tools
- expected output
- guardrails
- human approval point

## 4. Guardrails and Structured Outputs

Borrowed rule:

- Every generated artifact should have a schema or checklist.
- Every review should state pass, conditional pass, or block.
- Every high-impact claim should be labeled by source type.
- Every MCP action should have a dry run or preview before execution.

## 5. Scoped Memory

CrewAI supports crew memory and agent-scoped memory. Product Crew OS should keep:

- global user preference memory
- project memory
- role-specific project memory
- source ledger

Recall order:

1. project state
2. decision log
3. open questions
4. source ledger
5. relevant role memory
6. global user preferences

## 6. Checkpointing

CrewAI checkpointing allows recovery after failures and avoids rerunning completed work.

Product Crew OS should checkpoint after:

- artifact creation
- review completion
- stage change
- decision recording
- MCP action
- guardrail failure

## 7. Planning and Human Input Gates

Use lightweight preflight planning when:

- more than one stakeholder is triggered
- an MCP action may modify an external system
- a workflow stage jump is requested
- a PRD/design/data artifact affects engineering commitment

Ask for human confirmation before:

- sending external messages
- creating tickets/issues
- marking a stage approved
- storing global preferences
- changing stakeholder boundaries

## 8. Testing and Observability

Borrow CrewAI's testing mindset:

- run repeated scenarios
- score stage detection, agent routing, artifact quality, memory update, and next action clarity
- log stage detection, skill selection, agent summoning, guardrail results, artifact edits, checkpoints, and user corrections
