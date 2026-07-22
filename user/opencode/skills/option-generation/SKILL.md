---
name: option-generation
description: Generate 2-3 viable alternatives for a technical decision, evaluate with criteria, and recommend with rationale. Use before making architecture or technology choices.
---

# Option Generation

## Methodology
1. FRAME_DECISION: State the decision clearly. What are we choosing? What constraints apply?
2. GENERATE_ALTERNATIVES: Produce 2-3 feasible options. Each must be realistically implementable.
3. EVALUATE: Score each option on: performance, scalability, implementation complexity, maintainability, risk, and cost (time+money).
4. RECOMMEND: Pick one option with rationale. Explain why the recommended option beats alternatives on the most important criteria.
5. DOCUMENT_REJECTIONS: For each rejected option, state the specific criteria that eliminated it.

## Output Format
- Decision title (one line)
- Table: Option / Performance / Scalability / Complexity / Maintainability / Risk / Cost / Verdict
- Rationale paragraph
- Rejected options with elimination reason

## Anti-Patterns
- SINGLE_OPTION: Presenting only one choice with no alternatives
- STRAW_MAN: Including an obviously terrible option to make the preferred one look good
- MISSING_RATIONALE: Recommending without explaining why on the criteria that matter
