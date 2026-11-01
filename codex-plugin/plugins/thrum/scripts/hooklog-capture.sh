#!/bin/bash
# PreToolUse / PostToolUse hook: append the tool-call payload to
# .thrum/var/log/hooklog.jsonl through `thrum hooklog capture`, the same writer
# Claude's hooks use. The payload is read from stdin and passed straight through.
#
# Fail-open: logging is observation only. Codex treats exit 2 as a block.
# `thrum hooklog capture` itself never exits 2 on its own failure paths (it exits
# 1 for an unaccepted licence or a flag error, 4 for a write failure and 5 for a
# recovered panic), but a failure here must not turn into a denied tool call on
# any runtime, so it is reported on stderr and the script still exits 0. A tool
# call is never blocked by this hook.
set -u

command -v thrum >/dev/null 2>&1 || exit 0

thrum hooklog capture
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Thrum hooklog capture failed (status %s); tool call not blocked.\n' "$status" >&2
fi
exit 0
