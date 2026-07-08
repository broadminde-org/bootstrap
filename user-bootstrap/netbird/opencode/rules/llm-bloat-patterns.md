---
description: "Patterns that indicate LLM-generated bloat in context-set files"
---
<bloat_patterns>
- WALL_OF_PROSE: More than 3 consecutive paragraphs of explanatory text with no bullet structure. Rewrite as bullets.
- REDUNDANT_EXAMPLES: Same input/output scenario appears in two or more <example> blocks. Remove duplicates.
- HISTORICAL_NARRATIVE: Comments like "previously this used X, but we changed to Y because Z". Delete — git log owns history.
- CASE_ENUMERATION: Hand-written if/else-style scenario lists covering paths that never occur in practice. Replace with one general rule.
- OVER_SPECIFIED_ROUTING: A routing table with >8 entries covering hypothetical domains not present in the repo. Trim to active domains only.
- PERMISSION_SPRAWL: A `bash:` allow block with >6 patterns where several are redundant subsets of others. Consolidate.
- INLINE_DOCUMENTATION: Full README-style explanations of how a tool works embedded in agent body. Link to external docs instead.
</bloat_patterns>
