---
description: Mermaid diagram syntax rules and constraints for the netbird stack documentation.
---
## Mermaid Diagram Standards

All agents producing diagrams for codemap/architecture documents must use Mermaid syntax.
For canonical examples and generation procedures, use the `mermaid-diagram-generation` skill.

### Diagram Type Requirements

**Compose Stack Layering (`flowchart LR`):**
- Left-to-right flow: External client → Caddy (TLS) → reverse-proxied services
  (`@grpc` → netbird-server, `@backend` → netbird-server, default → dashboard)
- Nodes labeled with actual service names from `docker-compose.yml`
- Database node styled as cylinder `[("...")]` if any backend has a DB (this stack
  currently uses sqlite on a volume, not a container — surface that explicitly)

**Request Flow (`sequenceDiagram`):**
- Label participants with descriptive names (e.g. `Caddy as ReverseProxy`,
  `NB as NetbirdServer`, `Dash as Dashboard`)
- Show the full request lifecycle including TLS termination, reverse-proxy
  matching, and the upstream service
- Use `-->>` for return arrows

**Pipeline / init.d Execution (`graph TD`):**
- Draw top-down: `init.sh` orchestrator -> each numbered step in lexical order
- Label nodes with their full `<NN>-<name>/run.sh` path
- Use `subgraph` zones for the host tier (root-required) vs the app tier (deploy user)

**Schema (`erDiagram`):**
- One entity per table relevant to the stack
- Cardinality symbols (`||`, `|{`, `}o`, `}|-`, `o|`, `o{`) must accurately reflect
  foreign key constraints
- Relationship labels describe the semantic connection

### General Syntax Rules

- Prefer double quotes for node labels containing spaces or special characters
- Escape newlines inside labels with `\n`
- Do not use HTML tags inside Mermaid node labels (use Unicode or plain text)
- Ensure diagrams render without syntax errors before embedding in `.md` files
