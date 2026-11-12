---
name: thrum-team
description: Show active team members
---

List all active agents with their roles, modules, and current intents.

```bash
thrum team                   # Human-readable
thrum team --json            # Machine-readable
```

Use `thrum ping @name` to verify a specific agent's process is running; only the verdict `alive` means
running, and `unverified` or `owning-daemon-unreachable` mean unknown.
