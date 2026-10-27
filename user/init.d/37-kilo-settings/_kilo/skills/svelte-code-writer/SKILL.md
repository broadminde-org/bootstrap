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
- **`@sveltejs/mcp` CLI via `npx`**: the fallback for agents with `mcp: deny`
  (e.g. the deployed `frontend-specialist`) or when the MCP server is
  unreachable. The commands below are that CLI.

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
npx @sveltejs/mcp get-documentation "$state,$derived,$effect"
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
# Analyze inline code (escape $ as \$)
npx @sveltejs/mcp svelte-autofixer '<script>let count = \$state(0);</script>'

# Analyze a file
npx @sveltejs/mcp svelte-autofixer ./src/lib/Component.svelte

# Target Svelte 4
npx @sveltejs/mcp svelte-autofixer ./Component.svelte --svelte-version 4
```

**Important:** When passing code with runes (`$state`, `$derived`, etc.) via the terminal, escape the `$` character as `\$` to prevent shell variable substitution.

## Workflow

1. **Uncertain about syntax?** Run `list-sections` then `get-documentation` for relevant topics
2. **Reviewing/debugging?** Run `svelte-autofixer` on the code to detect issues
3. **Always validate** - Run `svelte-autofixer` before finalizing any Svelte component