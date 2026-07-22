# Modular Design

## Scope
All languages. Apply to every task that writes or refactors code.

## Rules
- FIX_ROOT: Fix the root cause, not the symptom. Ask "what's the real problem?" before implementing.
- MINIMAL_FIX: Prefer the smallest change that works. One-liners over multi-file rewrites.
- NO_OVERABSTRACT: Don't extract abstractions for hypothetical reuse. One concrete use → inline.
- SINGLE_RESPONSIBILITY: One function/module does one thing. If the name needs "and" or "or", split it.
- ZERO_VALUE: Types must have a useful zero value. No "is initialized" booleans. No half-constructed spaghetti with `Init()`.
- SMALL_INTERFACES: 1-2 methods per interface. Compose small interfaces rather than one monolithic God-interface.
- CONSISTENT_RECEIVERS: All methods on a type use the same receiver style (pointer or value). Mixing triggers vet warnings.
