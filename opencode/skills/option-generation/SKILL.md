---
name: option-generation
description: Generate 2–3 viable alternatives, evaluate, and recommend with rationale
---
<purpose>Offer balanced architectural choices by presenting multiple feasible options.</purpose>
<steps>
1. frame_decision: state the question in one sentence
2. generate_alternatives: list 2–3 feasible options with short names and descriptions
3. evaluate: compare each on performance, scalability, complexity, maintainability, risk, cost
4. recommend: select one with rationale
5. document_rejections: note strongest reason each non-selected option was rejected
</steps>
<output_format>
- Decision title line
- Table of alternatives with criteria and verdict
- Rationale paragraph
</output_format>
<anti_patterns>
- single_option: do not present only one
- straw_man: do not construct straw-man alternatives — all options must be genuinely viable
- missing_rationale: always include rationale
</anti_patterns>