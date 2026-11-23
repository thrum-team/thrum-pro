---
name: load-context
description:
  Restore your session after compaction or session restart by running thrum prime
---

Run `thrum prime --to-file` and read the file it writes to restore your session. The briefing includes your restart
snapshot, personal state, and committed-work queue.

```bash
thrum prime --to-file
```

If the output was truncated, read the file it was saved to, page by page; a second prime cannot redeliver your restart snapshot.
