# MCP Tools Usage

## Scope
Any task using MCP tooling (build, test, dev, update, or standards servers).

## Tool Families

### Async Quintets
Long-running tasks use a 5-tool async pattern:
- `{family}_start` — begin the operation, returns run_id
- `{family}_status` — poll progress by run_id
- `{family}_cancel` — abort by run_id
- `{family}_result` — get final output when complete
- `{family}_list` — list all current/past runs

### Read-Only / Sync Tools
- `{server}_diff` — diff between two states
- `{server}_feedback` — feedback on a previous result
- `{server}_audit` — audit state/config

## Progressive Disclosure Pattern
- SEARCH first for compact results (titles + snippets)
- GET only the matches you need — never fetch all content speculatively
- Resources (`resource://id`) are for static reference data. Tools are for actions.

## Usage Rules
- STATE_CHECK: Before starting a new long-running task, call `{family}_list` to see if one is already running.
- TIMEOUT: Poll status every 10-30s. Report to user if no progress for 2 minutes.
- CANCEL_STALE: If a previous run is stuck (status unchanged for >10 minutes), cancel and restart.
- RESULT_FIRST: Always check for a completed result before re-running the same task.

## Anti-Patterns
- START_IGNORE_LIST: Calling `{family}_start` without checking `{family}_list` first
- NEVER_POLL: Starting a task and waiting without polling status
- LOAD_ALL_SPECULATIVE: Fetching every standard/document instead of searching first
