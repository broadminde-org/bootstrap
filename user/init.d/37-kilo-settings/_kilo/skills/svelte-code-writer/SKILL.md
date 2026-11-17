---
name: svelte-code-writer
description: >-
  Write correct Svelte 5 and SvelteKit code using the @sveltejs/mcp CLI —
  list-sections, get-documentation, and svelte-autofixer via npx. USE FOR
  writing, reviewing, or debugging Svelte components, especially runes
  ($state, $derived, $effect), and for validating components with the
  autofixer before finishing. DO NOT USE FOR non-Svelte frontend work.
---

# Svelte Code Writer

## CLI tools

Two access paths exist for the same Svelte documentation service:

- **Remote `svelte` MCP server** (seeded in `~/.config/kilo/kilo.json`): when
  `svelte_list-sections` / `svelte_get-documentation` / `svelte_svelte-autofixer`
  tools are available to this agent, prefer them — no local install needed.
- **Already-available `@sveltejs/mcp` CLI**: an alternative when MCP transport
  is denied or unavailable, only if the underlying documentation/validation
  action, Bash, network, and every required side effect are independently
  authorized. Transport denial alone does not deny the underlying action.

Do not use an alternate tool to circumvent denial of the underlying action,
Bash, or network. `npx` can resolve/download packages and prepare caches;
those are separate side effects, not implicit authorization to install.
Establish an already-available invocation with no unauthorized preparation
before using the examples below. Otherwise report the unavailable required
check or obtain specific authority; do not claim validation passed.

CLI usage:

### List documentation sections

```bash
npx @sveltejs/mcp list-sections
```

Lists all available Svelte 5 and SvelteKit documentation sections with titles and paths.

### Get documentation

```bash
npx @sveltejs/mcp get-documentation "<section1>,<section2>,..."
```

Retrieves full documentation for specified sections. Use after `list-sections` to fetch relevant docs.

**Example:**

```bash
npx @sveltejs/mcp get-documentation '$state,$derived,$effect'
```

### Svelte autofixer

```bash
npx @sveltejs/mcp svelte-autofixer "<code_or_path>" [options]
```

Analyzes Svelte code and suggests fixes for common issues.

**Options:**

- `--async` - Enable async Svelte mode (default: false)
- `--svelte-version` - Target version: 4 or 5 (default: 5)

**Examples:**

```bash
# Analyze inline code (single quotes preserve literal runes)
npx @sveltejs/mcp svelte-autofixer '<script>let count = $state(0);</script>'

# Analyze a file
npx @sveltejs/mcp svelte-autofixer ./src/lib/Component.svelte

# Target Svelte 4
npx @sveltejs/mcp svelte-autofixer ./Component.svelte --svelte-version 4
```

**Important:** Use shell single quotes for literal runes (`$state`, `$derived`, etc.); inside single quotes do not add a backslash before `$`. Prefer an exact file path for complex code. Read the target Svelte version from project/installed metadata and async configuration rather than assuming CLI defaults.

## Workflow

1. **Check authority/availability.** Prefer authorized MCP tools; use an independently authorized already-available CLI only under the boundary above.
2. **Uncertain about syntax?** Run `list-sections` then `get-documentation` for relevant topics, without unauthorized network/package preparation.
3. **Reviewing/debugging?** Run `svelte-autofixer` on the code to detect issues.
4. **Validate before finalizing.** Run the autofixer for Svelte components and again after correcting reported issues. Keep project-required checks; report an unavailable/denied required check rather than installing or claiming completion.
