---
description: Mermaid diagram syntax rules and constraints for the netbird stack documentation.
---
## Mermaid Diagram Standards

All agents producing diagrams for codemap/architecture documents must use Mermaid syntax.
For canonical examples and generation procedures, use the `mermaid-diagram-generation` skill.

### Diagram Type Requirements

**Compose Stack Layering (`flowchart LR`):**
- Left-to-right flow: External client → reverse proxy (TLS) → upstream services.
- Label nodes with actual service names from `docker-compose.yml`.
- Database node styled as cylinder `[("...")]` if any backend has a DB.

**Request Flow (`sequenceDiagram`):**
- Label participants with descriptive names derived from the actual service names.
- Show the full request lifecycle including TLS termination, reverse-proxy
  matching, and the upstream service.
- Use `-->>` for return arrows.

**Pipeline / init.d Execution (`graph TD`):**
- Draw top-down: `init.sh` orchestrator -> each numbered step in lexical order.
- Label nodes with their full `<NN>-<name>/run.sh` path.
- Use `subgraph` zones when there are distinct tiers (e.g. root tier vs. user tier).

**Schema (`erDiagram`):**
- One entity per table relevant to the stack.
- Cardinality symbols (`||`, `|{`, `}o`, `}|-`, `o|`, `o{`) must accurately reflect
  foreign key constraints.
- Relationship labels describe the semantic connection.

### General Syntax Rules

- Prefer double quotes for node labels containing spaces or special characters
- Escape newlines inside labels with `\n`
- Do not use HTML tags inside Mermaid node labels (use Unicode or plain text)
- Ensure diagrams render without syntax errors before embedding in `.md` files
