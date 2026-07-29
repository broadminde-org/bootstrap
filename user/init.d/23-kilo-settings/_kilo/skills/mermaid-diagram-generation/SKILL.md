---
name: mermaid-diagram-generation
description: Generate Mermaid diagrams from source code and configuration files. Use when creating or updating architecture docs, pipeline diagrams, or data models.
---

# Mermaid Diagram Generation

## Diagram Types & Sources

### flowchart LR — System/Service Layering
- **Source**: docker-compose.yml, service configs, reverse proxy config
- **Layout**: Left-to-right. Client → Gateway (TLS) → backend services
- **Nodes**: Label with actual service names from compose file
- **Edges**: Label with protocol (HTTP, gRPC, TCP) and port

### sequenceDiagram — Request Flows
- **Participants**: Client, gateway, backend services
- **Include**: TLS termination, auth/header forwarding, upstream routing, response path
- **Arrows**: `->>` for forward calls, `-->>` for return arrows; label with method/purpose

### graph TD — Pipeline/CI Steps
- **Source**: CI config, init.d directory, Makefile targets
- **Layout**: Top-down from trigger/orchestrator; group tiers with `subgraph` (build, test, deploy)
- **Numbering**: Use step numbers if pipeline is sequentially numbered

### graph TD — Route Map
- **Source**: Reverse proxy config, API gateway routes, middleware chain
- **Nodes**: Named route matchers + wildcard/default routes
- **Edges**: Label with upstream service name

### erDiagram — Data Models
- **Source**: ORM models, SQL schema, protobuf definitions
- **Entities**: One per table/collection/message type
- **Cardinality**: `||--o{` (one-to-many), `||--||` (one-to-one), `}o--o{` (many-to-many)
- **Fields**: Include primary key, foreign keys, and significant non-key fields

## Syntax Rules
- Double-quote labels containing spaces
- Escape `\n` for line breaks in labels
- No HTML tags

## Anti-Patterns
- **LOST_LAYERS**: Diagram shows services that don't exist in the actual config
- **WRONG_DIRECTION**: Using `-->` when it should be `-->>`
- **MISSING_TLS**: Skipping TLS termination in request flow diagrams
- **NO_SUBGRAPH**: Flat graph when tiers exist

## Validation
- Validate all diagrams before embedding in documents
- Export: `mmdc -i diagram.mmd -o diagram.svg`
