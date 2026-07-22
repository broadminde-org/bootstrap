# Lifecycle Management

## Scope
Resource lifecycle work: create/delete pairs, provision/teardown, start/stop cycles.

## Rules
- SYMMETRIC: Every Create must have a corresponding Delete. Every Up must have a corresponding Down.
- INVENTORY: List all resources before creating or destroying. Know what exists.
- ORPHAN: Clean up orphaned resources (containers, volumes, networks) before applying new state.
- PRE_CLEAN: Remove stale state (stopped containers, dangling images, stale locks) before provisioning.
- BEST_EFFORT_DELETE: Deletion must work even when resources are partially created. Use `|| true` guards or `--force` flags.
- TEST_CYCLE: Test the full create/delete cycle at least once before declaring a lifecycle script complete.

## Anti-Patterns
- CREATE_ONLY: Script only does `docker compose up -d` with no corresponding `down`
- STALE_LOCK: Cleanup fails because of a leftover PID file or lock from a previous run
