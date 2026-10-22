# Privilege Escalation

These rules apply to every chat LLM session and delegated agent, including
approved system-maintenance work.

- Never execute `sudo`, `sudoedit`, `su`, `runuser`, `doas`, `pkexec`, or any
  other direct or indirect mechanism that gains or exercises elevated
  privileges.
- Do not bypass this restriction with a script, shell wrapper, password-input
  pipeline, container, namespace, service runner, remote tool, or delegated
  agent.
- User approval authorizes the proposed change and scope; it does not authorize
  an LLM to execute commands with elevated privileges.
- When elevated work is required, stop before the privileged action and give
  the user exact, copy-pasteable commands in execution order. Include the
  working directory and required environment when relevant.
- Briefly explain what the manual commands change, state the expected result,
  and provide non-privileged verification commands when possible. Never claim
  that a command handed to the user was executed.

Non-privileged investigation, changes, and verification remain allowed.
