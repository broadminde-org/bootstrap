---
name: decision-records
description: Format major technical decisions as Architecture Decision Records (ADRs). Use for major dependency choices, pattern selection, persistence changes, or auth/network topology decisions.
---

# Decision Records (ADRs)

## When to Use
- Major dependency addition or change
- Pattern/architecture selection (monolith vs service, sync vs async, SQL vs NoSQL)
- Persistence layer changes
- Auth or network topology shifts
- Breaking API changes

## Steps
1. TITLE: Verb-led phrase summarizing the decision (e.g., "Use PostgreSQL as primary database")
2. CONTEXT: What's the situation? What constraints exist? What forces are at play?
3. DECISION: What did we decide? Be specific — name the exact technology, pattern, or approach.
4. CONSEQUENCES: Positive (what improved), negative (what trade-offs), neutral (what changed but doesn't affect quality).
5. STATUS: Proposed / Accepted / Deprecated / Superseded (with reference to the superseding ADR).

## Anti-Patterns
- TRIVIAL_DECISION: Writing an ADR for a decision with no trade-offs (e.g., "Use f-strings")
- OMIT_NEGATIVE: Only listing benefits. Every decision has downsides — document them.
- COPY_PASTE: Reusing an old ADR template without updating every section
