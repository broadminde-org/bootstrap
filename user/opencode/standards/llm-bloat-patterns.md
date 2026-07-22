# LLM Bloat Patterns

## Scope
Editing agent context files (rules, agents, commands, skills, standards).

## Anti-Patterns to Catch

- WALL_OF_PROSE: >3 consecutive paragraph blocks → rewrite as bullets or XML-anchored rules
- REDUNDANT_EXAMPLES: Same scenario in 2+ `<example>` blocks → keep the best one
- HISTORICAL_NARRATIVE: "Previously we used X, changed to Y" → delete. Git log owns history.
- CASE_ENUMERATION: Hand-written if/else scenario lists → replace with one general rule
- OVER_SPECIFIED_ROUTING: Routing tables with >8 entries for hypothetical domains → trim to actual domains in use
- PERMISSION_SPRAWL: Bash allow blocks with >6 redundant patterns → consolidate with globs
- INLINE_DOCUMENTATION: README-style explanations in agent body → move to standards, reference by name
- FORMAT_TABLES: Markdown tables with |---|---| → convert to colon-separated lists

## Self-Application Rule

The context set itself must be held to these standards. Every standards file, rule file, and agent definition must pass bloat inspection. The agent-tuner enforces this.
