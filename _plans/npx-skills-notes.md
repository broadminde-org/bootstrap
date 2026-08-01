# npx skills — Notes

## Scope: global vs project

- `npx skills add <pkg>` without `-g` installs to **project** scope (`.kilocode/skills/` in CWD).
- `npx skills add <pkg> -g` installs to **global** scope (user-level, `~/.kilocode/skills/`).
- Kilo picks up skills from both — project `.kilo/` / `.kilocode/` and global `~/.kilo/` / `~/.kilocode/` — with project winning on name conflicts.

## Declarative / lockfile install

- `skills experimental_install` — restores skills from a `skills-lock.json` file (like VSCode `extensions.json`).
- `skills experimental_sync` — syncs skills from `node_modules` into agent directories.
- Both are **experimental**; lockfile format may change.

## Current init.d usage

`40-npx-skills/run.sh` installs 4 skills globally:
- `handoff` (mattpocock/skills)
- `design-an-interface` (mattpocock/skills)
- `python-mcp-server-generator` (github/awesome-copilot)
- `async-python-patterns` (wshobson/agents)

## Search (`skills find`)

- Only option is `--owner <owner>` to filter by GitHub owner. No `--json`, no `--verbose`.
- Passing `--json` is silently ignored and corrupts results (different/lower-ranked entries returned).
- Output is formatted text only: `owner/repo@skill_name`, install count, URL.
- Truncates to ~6 results when many matches are found.

## Search API → use @mastra/skills-api

**Decision: Use `@mastra/skills-api`** — open-source, no auth, 34K+ skills, runnable locally.

- GitHub: `mastra-ai/skills-api` (34 stars, MIT)
- 34,000+ skills from 2,800+ repos, scraped from skills.sh.
- `GET /api/skills?query=<text>&sortBy=installs|name&sortOrder=desc|asc&page=1&pageSize=20` (max 100)
- `GET /api/skills/top` — top skills by installs.
- `GET /api/skills/:owner/:repo/:skillId` — single skill detail.
- `GET /api/skills/:owner/:repo/:skillId/files` — file contents from GitHub.
- `GET /api/skills/:owner/:repo/:skillId/content` — parsed SKILL.md.
- `GET /api/skills/by-source/:owner/:repo` — all skills from a repo.
- Library usage: `import { skills, metadata, getTopSkills } from '@mastra/skills-api'`.
- Data refresh: `pnpm scrape` or `POST /api/admin/refresh`.
- Storage: bundled data → filesystem → S3 (priority order).
- Last commit: **Mar 11, 2026** — scraper uses skills.sh's paginated API (`api/skills/all-time/{page}`). Initial commit Jan 30, 2026. ~5 months old; bundled data will be stale but `pnpm scrape` fetches live data from skills.sh.
- Small but active (20 commits, 2 PRs, Mastra team).

### Alternative: Official skills.sh REST API (Vercel)

- `https://skills.sh/api/v1/skills/search?q=<query>&limit=N` — fuzzy/semantic search, JSON.
- **Requires Vercel OIDC token** (scoped per team/project). No unauthenticated access.
- Rate limit: 600 req/min. More endpoints (audit, curated, detail+files).
- Rejected for now due to auth requirement; revisit if `@mastra/skills-api` proves insufficient.

## Ideas / TODOs

- Language-specific skills (Go, Rust, etc.) should be repo-scoped, not global.
- Consider a `skills-lock.json` per repo for declarative install of repo-scoped skills.
- Could wire `skills experimental_install` into a repo's init/setup flow.
