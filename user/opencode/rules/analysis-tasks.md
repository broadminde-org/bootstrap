---
description: Methodology for read-only analysis, review, and audit tasks
---
<trigger>
Apply when the task is read-only: analyze, review, assess, audit, report, check,
"take a look at", "what's configured", "what's missing", "is anything wrong".
Do NOT apply to implementation tasks (write, edit, create).
</trigger>

<exploration_order>
Before writing any report, complete this sequence. Run independent steps in parallel:

1. List the named component's directory with ls -la on all subdirectories — detect symlinks explicitly
2. List the project's plans directory (_plans/ or equivalent) — read every plan that references the component, prior sessions, or credentials
3. Read any build or scan steps in init.d/ that involve the component
4. Grep the active context set (.kilo/rules/, .kilo/commands/, .kilo/skills/) for the component name
5. Grep the staging context set (.kilo-staging/rules/, .kilo-staging/commands/) with the same pattern if the directory exists
6. Grep codemap.md and README.md for the component name
</exploration_order>

<verification_required>
These checks are mandatory before closing any report:

- PILOT_TRUTH: If the user states whether a component was or was not used in a prior session or pilot, verify against plan files before accepting it. State true or false with a direct quote.
- PLAN_REALITY: For every plan file with status "Draft" or "Awaiting sign-off", compare the documented "before" state against actual files on disk. State whether each plan is fully implemented, partially implemented, or genuinely pending.
- RULE_ACCURACY: For any rule or context file that references the component (image names, env var names, file paths), cross-check each claim against the actual source files. Flag any mismatch as stale.
</verification_required>

<report_format>
1. Files on disk — table: path | purpose | status (complete / empty / stale)
2. Prior usage — true or false with direct quote as evidence
3. Plan status — table: plan file | documented status | on-disk reality | verdict
4. LLM context coverage — what the context set mentions, what is absent or stale
5. Issues and gaps — inconsistencies, missing coverage, stale documentation
</report_format>
