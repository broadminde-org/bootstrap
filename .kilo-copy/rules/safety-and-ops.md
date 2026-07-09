---
description: "Operational safety: timeouts, Docker hygiene, SSH best practices"
---
<timeouts>
- Use `--max-time` or flags to prevent hangs; add timeouts for tests and builds.
- Check non-blocking commands every 10–30s; report after 2m of no progress.
</timeouts>
<docker_compose>
- Always use `--remove-orphans`; never `sudo docker`; advise docker group fix on perm errors.
</docker_compose>
<npm>
- Never use `sudo npm`; advise setup of user prefix on EACCES.
</npm>
<ssh_ops>
- Set ConnectTimeout=10 and ServerAliveInterval=5; reuse connections via ControlMaster.
- Example: `ssh -o ControlMaster=auto -o ControlPath=...`
</ssh_ops>