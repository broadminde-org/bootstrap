---
name: decision-records
description: Format major technical decisions as ADRs with context and consequences
---
<purpose>Record significant architectural choices and their rationale for future reference.</purpose>
<when_to_use>
- major dependency, pattern selection, persistence changes, auth/network topology shifts
</when_to_use>
<steps>
1. title: concise decision statement
2. context: forces, constraints, goals
3. decision: clear unambiguous choice
4. consequences: positive, negative, neutral
5. status: Proposed/Accepted/Deprecated/Superseded
</steps>
<output_format>
- Title line
- Status
- Context section
- Decision section
- Consequences list
</output_format>
<anti_patterns>
- trivial_decision
- omit_negative
- copy_paste_without_update
