# Agent MD Refactor

A skill that transforms bloated agent instruction files into clean, organized documentation using progressive disclosure principles.

Based on https://x.com/mattpocockuk/status/2012906065856270504 (Matt Pocock's Prompt Idea)

## Purpose

Over time, agent instruction files like `CLAUDE.md`, `AGENTS.md`, or `COPILOT.md` tend to grow into unwieldy documents containing hundreds of lines of mixed instructions. This creates several problems:

- **Context waste**: Every task loads the entire file, even when most instructions are irrelevant
- **Maintenance burden**: Finding and updating specific instructions becomes difficult
- **Contradictions**: Conflicting guidelines accumulate without being noticed
- **Signal-to-noise ratio**: Important rules get buried among obvious or vague statements

This skill applies **progressive disclosure** while preserving binding safety,
permissions, trust, approval gates, and required checks. Read `SKILL.md` for the
preservation contract before editing: links alone do not load instructions,
external executors need self-contained essentials, and size is advisory rather
than proof of savings or an acceptance gate.

## When to Use

Use this skill when you need to clean up agent instruction files. Common trigger phrases include:

- "refactor my AGENTS.md" / "refactor my CLAUDE.md"
- "split my agent instructions"
- "organize my CLAUDE.md file"
- "my AGENTS.md is too long"
- "progressive disclosure for my instructions"
- "clean up my agent config"

**Good candidates for refactoring:**

- Root agent files exceeding 50-100 lines
- Files mixing multiple unrelated topics (testing, code style, architecture, etc.)
- Documents that have grown organically without structure
- Files containing contradictory or redundant instructions

## How It Works

The skill follows a systematic 5-phase process:

### Phase 1: Find Contradictions

Before restructuring, the skill identifies conflicting instructions that need resolution. Examples include contradictory style guidelines ("use semicolons" vs "no semicolons") or incompatible workflow instructions. Each contradiction is surfaced with a question for the user to resolve.

### Phase 2: Identify the Essentials

Extracts only what truly belongs in the root file - information that applies to every single task:

| Keep in Root | Move Out |
|-------------|----------|
| One-sentence project description | Language-specific conventions |
| Non-standard package manager | Testing guidelines |
| Custom build/test commands | Code style details |
| Critical overrides | Framework patterns |
| Universal rules (100% of tasks) | Documentation standards |

### Phase 3: Group the Rest

Organizes remaining instructions into logical categories like:

- `typescript.md` - Type patterns, strict mode rules
- `testing.md` - Test frameworks, coverage, mocking
- `code-style.md` - Formatting, naming, structure
- `git-workflow.md` - Commits, branches, PRs
- `architecture.md` - Patterns, folder structure

### Phase 4: Create the File Structure

Generates the new file hierarchy with properly linked documentation:

```
project-root/
├── CLAUDE.md              # Minimal root with links
└── .claude/               # Categorized instructions
    ├── typescript.md
    ├── testing.md
    ├── code-style.md
    └── architecture.md
```

### Phase 5: Flag for Deletion

Identifies instructions that should be removed entirely:

- **Redundant**: "Use TypeScript" in a TypeScript project
- **Too vague**: "Write clean code" without specifics
- **Overly obvious**: "Don't introduce bugs"
- **Default behavior**: "Use descriptive variable names"
- **Outdated**: References to deprecated APIs

## Key Features

- **Contradiction detection**: Surfaces conflicting instructions before restructuring
- **Intelligent categorization**: Groups related instructions into logical files
- **Root file focus**: Retains binding requirements and effective task-specific routing without a line quota
- **Deletion recommendations**: Identifies instructions wasting context tokens
- **Template-driven output**: Consistent structure across all generated files
- **Link verification**: Ensures all references between files are valid

## Usage Examples

### Basic Refactoring

```
User: refactor my CLAUDE.md

Kilo: I'll analyze your CLAUDE.md file and refactor it using progressive
disclosure principles...
```

### Specific File

```
User: my AGENTS.md is too long, can you split it up?

Kilo: I'll review your AGENTS.md and organize it into focused, linked files...
```

### After a Project Grows

```
User: organize my agent config - it's gotten out of control

Kilo: I'll apply the 5-phase refactoring process to clean up your
agent instructions...
```

## Output

After running the skill, you get:

**Focused root file (illustrative structure, not a size requirement):**
```markdown
# Project Name

One-sentence description of the project.

## Quick Reference

- **Package Manager:** pnpm
- **Build:** `pnpm build`
- **Test:** `pnpm test`

## Detailed Instructions

- [TypeScript Conventions](.claude/typescript.md)
- [Testing Guidelines](.claude/testing.md)
- [Code Style](.claude/code-style.md)
```

**Organized linked files with consistent structure:**
```markdown
# Testing Guidelines

## Overview
Brief context for when these guidelines apply.

## Rules

### Unit Tests
- Specific, actionable instruction
- Another specific instruction

## Examples

### Good
[code example]

### Avoid
[code example]
```

**Deletion report:**
```markdown
## Flagged for Deletion

| Instruction | Reason |
|-------------|--------|
| "Write clean, maintainable code" | Too vague to be actionable |
| "Use TypeScript" | Redundant - project is already TS |
```

## Best Practices

### Before Refactoring

1. **Inspect current state** - Review status/diff and instruction loading; preserve unrelated work. Commit/stage only with explicit user authority
2. **Identify your goals** - Know what problems you want to solve
3. **Gather all instruction files** - Some projects have instructions scattered across multiple locations

### During Refactoring

1. **Resolve contradictions first** - Do not proceed until conflicts are addressed
2. **Preserve effective loading** - Move requirements only after verifying their scope, precedence, trust, and point-of-use loading
3. **Group by need** - File counts are advisory, not a reason to fragment or delete requirements
4. **Record dispositions** - Retain safety/checks or verify an authoritative loaded replacement; presumed model knowledge is not sufficient

### After Refactoring

1. **Verify all links work** - Test that referenced files exist
2. **Check for lost instructions** - Ensure nothing important was dropped
3. **Qualify loading when authorized** - Real task/client tests require separate applicable runtime authority; source/static review alone cannot establish equivalent behavior

## Anti-Patterns to Avoid

| Avoid | Why | Instead |
|-------|-----|---------|
| Keeping everything in root | Bloated, hard to maintain | Split into linked files |
| Too many categories | Fragmentation, navigation overhead | Consolidate related topics |
| Vague instructions | Wastes tokens, no value | Be specific or delete |
| Deleting "obvious" safety rules | Removes binding protection | Retain or verify an authoritative loaded replacement |
| Deep nesting | Hard to navigate | Flat structure with links |

## Verification Checklist

After refactoring, verify:

- [ ] Root retains essential binding rules and task-specific routing; size is advisory
- [ ] All links to sub-files work correctly
- [ ] No contradictions remain between files
- [ ] Every instruction is specific and actionable
- [ ] Every requirement has a retained loaded home or verified inapplicability
- [ ] Each linked file is self-contained for its topic
- [ ] External-executor essentials, permissions, trust, approval gates, and acceptance checks remain intact

## License

MIT
