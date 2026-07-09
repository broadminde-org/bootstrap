---
name: context-gathering
description: Assess existing systems, constraints & non-functional requirements before design
---
<scope>
USE_BEFORE: design work begins
</scope>

<methodology>
1. INVENTORY: use codebase-inventory skill for file tree, deps & entry points
2. READ_DOCS: scan ADRs, RFCs, design docs
3. IDENTIFY_NFR: scale, latency, availability, compliance, budget constraints
4. MAP_DEBT: note legacy & technical debt constraints
5. ASSESS_TEAM: evaluate team size, expertise & operational maturity
6. DOCUMENT_ASSUMPTIONS: list unspecified items clearly
</methodology>

<anti_patterns>
- START_OPTIONS_EARLY: do not generate options before gathering context
- TRUST_SINGLE_SOURCE: do not treat one file/README as authoritative
</anti_patterns>