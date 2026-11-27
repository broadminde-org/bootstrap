---
name: svelte-code-writer
description: >-
  Write correct version-aware Svelte and SvelteKit code using authorized
  Svelte MCP tools or an already-prepared @sveltejs/mcp CLI. USE FOR
  writing, reviewing, or debugging Svelte components, especially runes
  ($state, $derived, $effect), and for validating components with the
  autofixer before finishing. DO NOT USE FOR non-Svelte frontend work.
---

# Svelte Code Writer

## CLI tools

Two documentation/validation access paths exist; their installed versions and
argument contracts may differ:

- **Remote `svelte` MCP server** (seeded in `~/.config/kilo/kilo.json`): when
  `svelte_list-sections` / `svelte_get-documentation` / `svelte_svelte-autofixer`
  tools are available to this agent, prefer them — no local install needed.
- **Already-available `@sveltejs/mcp` CLI**: an alternative when MCP transport
  is unavailable, only if the underlying documentation/validation
  action, Bash, network, and every required side effect are independently
  authorized. An unavailable transport is not permission to bypass a denial.

Do not use an alternate tool to circumvent denial of the underlying action,
Bash, or network. `npx` can resolve/download packages and prepare caches;
those are separate side effects, not implicit authorization to install.
Establish an already-available invocation with no unauthorized preparation
before using the examples below. Otherwise report the unavailable required
check or obtain specific authority; do not claim validation passed.

Inspect project `package.json`, lockfile, and installed `svelte/package.json`
when present to establish the exact target version (and report disagreements).
A dependency range alone is not an installed version; do not default to latest
or upgrade/prepare dependencies to resolve it. Read existing compiler async
configuration. Preserve Svelte 4/legacy components, valid stores/actions, and
the project's framework conventions; a small fix is not a migration mandate.

CLI examples below require that preflight. Prefer the prepared executable;
use `npx` only after establishing an invocation that will not resolve/download
packages or create unauthorized cache/environment state. Verify flags against
that CLI's local help or version-matched source under applicable authority.

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
# shellcheck disable=SC2016
npx @sveltejs/mcp get-documentation '$state,$derived,$effect'
```

### Svelte autofixer

```bash
npx @sveltejs/mcp svelte-autofixer "<code_or_path>" [options]
```

Analyzes Svelte code and suggests fixes for common issues.

**Options:**

- `--async` - Use only for supported async Svelte when the project's compiler
  configuration already enables it; never change that configuration implicitly.
- `--svelte-version` - Pass the exact project version if the selected interface
  supports semver; an interface accepting only a major cannot validate minor-API
  availability. Check that interface's supported values rather than its default.

**Examples:**

```bash
# Analyze inline code (single quotes preserve literal runes)
# shellcheck disable=SC2016
npx @sveltejs/mcp svelte-autofixer '<script>let count = $state(0);</script>'

# Analyze a file
npx @sveltejs/mcp svelte-autofixer ./src/lib/Component.svelte

# Target Svelte 4
npx @sveltejs/mcp svelte-autofixer ./Component.svelte --svelte-version 4
```

**Important:** Use shell single quotes for literal runes (`$state`, `$derived`, etc.); inside single quotes do not add a backslash before `$`. Prefer an exact file path for complex code. Read the target Svelte version from project/installed metadata and async configuration rather than assuming CLI defaults.

## Workflow

1. **Check authority/availability.** Prefer authorized MCP tools; use an independently authorized already-available CLI only under the boundary above.
2. **Select documentation.** Use authorized `list-sections`, then fetch only the sections relevant to the actual edit. Verify affected version-sensitive facts against official references; do not fetch every section or rely on current docs as proof an older project supports an API. If transport/startup is not authorized, use permitted official read-only sources and report required tool validation unavailable.
3. **Reviewing/debugging?** Run `svelte-autofixer` on the code to detect issues.
4. **Validate before finalizing.** Run the autofixer for Svelte components and again after correcting reported issues. Keep project-required checks; report an unavailable/denied required check rather than installing or claiming completion.

Load `svelte-core-bestpractices` for Svelte 5 runes work when available. Portable
minimum: writable derived overrides require 5.25+, attachments require 5.29+,
`createContext` requires 5.40+, and component await expressions require 5.36+
with existing `experimental.async` enabled. On older versions use supported
state/context/actions/await-block patterns; valid stores and actions remain
valid. Sources: [derived](https://svelte.dev/docs/svelte/$derived),
[attachments](https://svelte.dev/docs/svelte/@attach),
[context](https://svelte.dev/docs/svelte/svelte#createContext), and
[async](https://svelte.dev/docs/svelte/await-expressions). These gates do not
authorize conversion, upgrades, configuration changes, or waived checks.
