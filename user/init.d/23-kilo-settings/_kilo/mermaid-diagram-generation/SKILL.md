---
name: mermaid-diagram-generation
description: >
  Generate Mermaid diagrams from source code and configuration files.
  Use when creating or updating architecture docs, pipeline diagrams,
  data models, or request-flow documentation.
license: MIT
metadata:
  category: documentation
---

# Mermaid Diagram Generation

## Source-to-Diagram Mapping

| Diagram type         | Look for                                           |
|----------------------|----------------------------------------------------|
| flowchart / graph    | docker-compose.yml, service configs, route tables  |
| sequence diagram     | middleware chains, auth flows, API request paths   |
| graph (pipeline)     | CI config, Makefile, init/run scripts              |
| ER diagram           | ORM models, SQL schemas, protobuf definitions      |

## Rules

- Derive node labels from actual names in the source (service names, route
  paths, table names). Never invent names.
- Label edges with protocol (HTTP, gRPC, TCP), port, or upstream target.
- For sequence diagrams, include auth/header forwarding and response paths.
- For ER diagrams, include PKs, FKs, and significant non-key fields. Show
  cardinality: `||--o{` (one-to-many), `||--||` (one-to-one), `}o--o{`
  (many-to-many).
- For multi-step pipelines, group steps with `subgraph` by logical tier
  (build, test, deploy).
- Validate diagrams: `mmdc -i diagram.mmd -o diagram.svg`
