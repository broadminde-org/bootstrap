# Plan Lifecycle

- Apply this contract when creating, executing, reviewing, resuming, or updating plans, regardless of model or selected agent. Maintain plans only with write authority; read-only reviews report stale state without editing plans or creating archives.
- Maintain one current execution queue per workstream; independent workstreams may have separate plans. Reuse the current plan for the same workstream rather than creating competing queues.
- Make disposition, objective, current state, remaining ordered actions, concrete blockers, and acceptance easy to identify.
- Use dispositions `draft`, `active`, `blocked`, `completed`, or `historical`. Mark a superseded plan `historical` and point to its successor. Completed and historical plans are not executable queues.
- Update current state in place. Remove resolved blockers, obsolete actions, and superseded instructions rather than appending narrative handoffs or repeated amendments.
- Retain only completed-work summaries and exact current identifiers needed for continuation or admission. Link evidence instead of embedding logs, obsolete process histories, or investigation transcripts; never remove a required source or receipt identity merely to shorten a plan.
- Preserve authentic evidence and still-applicable decisions outside the executable queue. Reuse existing records instead of automatically creating an archive for every update.
- Reference applicable policies and contracts rather than repeating them. Make material acceptance or trust-model changes explicit under actual authority; compaction must never silently waive requirements.
- Map required checks to their acceptance purpose. One still-valid execution may satisfy overlapping requirements only when the governing contract permits reuse; explicit separate-run requirements remain binding. Reruns need a distinct purpose or invalidated evidence, including relevant source changes, without omitting required coverage.
- Treat plans as intent, not permission. Keep persistent goals and continuation summaries aligned with current state when the runtime permits; report stale retained objectives rather than treating them as current authority. Preserve separate commit, push, and deployment gates.
- Use size as a warning, not a completeness gate. Prefer compact queues; reassess repetition and history around 200 lines or 12,000 characters without dropping necessary execution requirements to meet a quota.
