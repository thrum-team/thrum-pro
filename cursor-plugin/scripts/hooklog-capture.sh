#!/bin/bash
# preToolUse / postToolUse / postToolUseFailure hook: append the tool-call record
# to .thrum/var/log/hooklog.jsonl through `thrum hooklog capture`, the same
# writer Claude's hooks use.
#
# `thrum hooklog capture` reads Claude's stdin schema, and `thrum hooklog detect`
# pairs records only on hook_event_name "PreToolUse" / "PostToolUse" with one
# shared tool_use_id. Cursor's payload differs, so this script translates it:
#   preToolUse                         -> PreToolUse
#   postToolUse, postToolUseFailure    -> PostToolUse (a failed call closes its pair)
#   any other event                    -> nothing is captured
#   session_id    <- session_id, else conversation_id
#   cwd           <- first non-empty of tool_input.cwd, cwd, workspace_roots[0]
#                    (Shell payloads carry cwd ""; Read/Write carry none)
#   duration_ms   <- round(duration), when numeric
#   tool_response <- tool_output (a JSON-encoded string; parsed when it is an
#                    object or array), or for a failure
#                    {error, failure_type, is_interrupt}
# tool_name, tool_use_id, tool_input and transcript_path pass through unchanged.
# Everything else is dropped on purpose; user_email is personal data and
# cursor_version, model, generation_id, conversation_id and workspace_roots do
# not belong in the log.
#
# Not every project is a thrum project: capture creates ./.thrum/var/log in its
# cwd when it finds no .thrum, so this script runs it only from a directory with
# a .thrum at or above it.
#
# Fail-open: logging is observation only. Cursor treats exit 2 as a block, so
# the script always exits 0: a failing capture is reported on stderr, a missing
# jq or thrum is silent. A tool call is never blocked by this hook, and nothing
# is written to stdout.
set -u

note() { printf 'Thrum hooklog capture %s; tool call not blocked.\n' "$1" >&2; }

# Read all of stdin byte-exact (no trailing-newline loss, no external cat).
IFS= read -r -d '' input || true

# A missing jq or thrum is not a failure of this hook: stay silent, like the
# Codex capture script and the other Cursor hook scripts.
command -v jq >/dev/null 2>&1 || exit 0
command -v thrum >/dev/null 2>&1 || exit 0

# has_thrum_dir: a .thrum directory at $PWD or any ancestor, the walk
# `thrum hooklog capture` itself does.
has_thrum_dir() {
    local d=$PWD
    while :; do
        [ -d "$d/.thrum" ] && return 0
        [ "$d" = / ] && return 1
        d=${d%/*}
        [ -n "$d" ] || d=/
    done
}

# run_capture <payload> <newline-suffix>: capture's stdout is dropped (hook
# stdout is parsed by Cursor), its stderr passes through.
run_capture() {
    local status
    printf '%s%s' "$1" "$2" | thrum hooklog capture >/dev/null
    status=$?
    if [ "$status" -ne 0 ]; then
        note "failed (status $status)"
    fi
    return 0
}

# Unparsable or non-object stdin: forward it as is; capture records an
# unparsable fallback. Only from a directory inside a thrum project.
if ! printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1; then
    has_thrum_dir && run_capture "$input" ""
    exit 0
fi

native=$(printf '%s' "$input" | jq -r '.hook_event_name // "" | if type == "string" then . else "" end') || exit 0
case "$native" in
    preToolUse) event=PreToolUse ;;
    postToolUse | postToolUseFailure) event=PostToolUse ;;
    *) exit 0 ;;
esac

normalized=$(printf '%s' "$input" | jq -c --arg event "$event" --arg native "$native" '
    def nonempty: select(type == "string" and length > 0);
    def parsed:
        . as $s
        | if type == "string" then
              (try ($s | fromjson) catch $s)
              | if type == "object" or type == "array" then . else $s end
          else . end;
    {
        hook_event_name: $event,
        tool_name: .tool_name,
        tool_use_id: .tool_use_id,
        session_id: (.session_id // .conversation_id),
        cwd: ([(.tool_input.cwd?), .cwd, (.workspace_roots[0]?)] | map(nonempty) | .[0]),
        tool_input: .tool_input,
        transcript_path: .transcript_path
    }
    + (if $event == "PostToolUse" and (.duration | type) == "number"
       then {duration_ms: (.duration | round)} else {} end)
    + (if $native == "postToolUse" then {tool_response: (.tool_output | parsed)}
       elif $native == "postToolUseFailure" then
           {tool_response: ({error: .error_message, failure_type: .failure_type, is_interrupt: .is_interrupt}
                            | with_entries(select(.value != null)))}
       else {} end)
    | with_entries(select(.value != null))
' 2>/dev/null) || {
    note "skipped: could not normalize the payload"
    exit 0
}
[ -n "$normalized" ] || exit 0

# Run capture from the project directory the payload names (its process cwd
# decides which .thrum it finds); fall back to the hook's own cwd.
dir=$(printf '%s' "$normalized" | jq -r '.cwd // ""')
if [ -n "$dir" ] && [ -d "$dir" ]; then
    cd "$dir" || true
fi
has_thrum_dir || exit 0

run_capture "$normalized" $'\n'
exit 0
