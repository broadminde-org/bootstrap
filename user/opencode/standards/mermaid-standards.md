# Mermaid Diagram Standards

## Scope
All diagram generation. Apply when creating or editing Mermaid diagrams.

## Diagram Types & Conventions

### flowchart LR — System Layering
- Left-to-right layout
- Nodes labeled with actual service/component names
- Client → Gateway (TLS) → Backend services

### sequenceDiagram — Request Flows
- Full lifecycle including TLS termination
- `-->>` for return arrows (dashed)
- `->>` for forward calls (solid)
- Label arrows with method/purpose

### graph TD — Pipelines
- Top-down from orchestrator
- `subgraph` zones for logical tiers
- Numbered steps when applicable

### erDiagram — Data Models
- One entity per table/collection
- Accurate cardinality: `||--o{` (one-to-many), `||--||` (one-to-one), `}o--o{` (many-to-many)
- Include key fields in entity descriptions

## Syntax Rules
- Double-quote labels with spaces
- Escape `\n` for line breaks in labels
- No HTML tags
- Validate diagram syntax before embedding in docs
- Auto-format: `mmdc -i diagram.mmd -o diagram.svg` for export

## Anti-Patterns
- LOST_LAYERS: Diagram shows services that don't exist in the actual config
- WRONG_DIRECTION: Using `-->` when it should be `-->>`
- MISSING_TLS: Skipping TLS termination in request flow diagrams
- NO_SUBGRAPH: Flat graph when tiers exist
