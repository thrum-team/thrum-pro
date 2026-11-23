---
name: wait
description: Block until a message arrives, only when not in tmux (tmux agents get messages in the pane)
argument-hint: '[--timeout 30s]'
---

Block until a message arrives or timeout expires. Used by the message-listener
pattern.

```bash
thrum wait                           # Default 30s timeout
thrum wait --timeout 120s            # 120 seconds
thrum wait --after -15s --json # Include messages sent up to 15s ago; JSON output
```

See LISTENER_PATTERN.md resource for the full background listener template.
