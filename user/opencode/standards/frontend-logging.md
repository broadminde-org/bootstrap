# Frontend Logging

## Scope
Setting up or debugging frontend log pipelines (SvelteKit, Next.js, or any JS framework).

## Architecture
- CONSOLE_DURING_DEV: Browser console in development. Structured remote transport in production.
- STRUCTURED_OUTPUT: JSON log lines. Include level, component, message, userId (if available), requestId, timestamp.
- ERROR_BOUNDARY: Every route/component boundary must catch errors and log before presenting fallback UI.

## Transport Rules
- NO_SYNC_XHR: Never use synchronous XMLHttpRequest for log shipping
- BATCH: Buffer log lines. Ship every 2s or every 50 lines, whichever comes first.
- RETRY_BACKOFF: Exponential backoff on ship failure (1s, 2s, 4s, 8s, max 30s). Drop after 5 retries.
- COMPRESSION: gzip payloads >1KB

## Log Levels
- ERROR: User-impacting failure, stack trace
- WARN: Degraded but functioning (retry succeeded, fallback used)
- INFO: Session start, navigation, API call start/end
- DEBUG: Component render, state change, event detail

## Privacy
- NO_PII_IN_LOGS: Never log email, IP, physical address, or full names to remote transport.
- REDACT: PII fields in log payloads must be redacted (`[REDACTED]`) before shipping.
