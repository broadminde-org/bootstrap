---
description: Search and retrieve coding standards, guidelines, and reference material
agent: code
---

# Standards

## Usage
`/standards <query>`

Searches the standards library for coding guidelines, patterns, and reference material.
Returns matching standards with a summary. Use `/standards get <id>` to read the full content.

## Methodology
1. SEARCH: Call `standards_search(query)` to find relevant standards.
2. SUMMARIZE: Present matching standards with title and one-line summary.
3. RETRIEVE: If the user wants the full content, call `standards_get(id)`.
