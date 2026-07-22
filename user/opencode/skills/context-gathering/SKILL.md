---
name: context-gathering
description: Assess existing systems, constraints, and non-functional requirements before design work begins. Run BEFORE option-generation or plan-writing.
---

# Context Gathering

## Scope
Run before any design or architecture work. Never start generating options without this step.

## Methodology
1. INVENTORY: Run codebase-inventory skill to understand existing structure.
2. READ_DOCS: Read existing ADRs, RFCs, design docs, architecture decision records.
3. IDENTIFY_NFR: Extract non-functional requirements — scale targets, latency budgets, availability SLA, compliance (GDPR, SOC2), budget constraints.
4. MAP_DEBT: Identify legacy systems, known technical debt, and migration-in-progress.
5. ASSESS_TEAM: Note team size, expertise distribution, and development maturity.
6. DOCUMENT_ASSUMPTIONS: Every assumption not verified by source → list explicitly with [ASSUMPTION] prefix.

## Anti-Patterns
- START_OPTIONS_EARLY: Generating alternatives before understanding constraints
- TRUST_SINGLE_SOURCE: Relying on one doc or one person's claim without cross-reference
- MISSING_NFR: Designing without knowing scale/latency/availability targets
