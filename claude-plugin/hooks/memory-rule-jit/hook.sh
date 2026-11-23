#!/usr/bin/env bash
# PreToolUse hook: JIT agent-rule injection.
#
# Reads PreToolUse JSON from stdin. For Edit/Write/MultiEdit tools:
#   1. Extracts the file path(s) from tool_input.
#   2. Fetches agent_rule records (zoom=full) from thrum memory list.
#   3. Matches rules whose triggers.path_globs match the path AND
#      triggers.tools include the current tool.
#   4. Consults per-session dedup file; skips already-injected rule IDs.
#   5. Hard rules (enforcement=hard): emits permissionDecision=deny with the
#      reason, plus the rule text as additionalContext, exits 0.
#   6. Soft rules (enforcement=soft): emits the rule text as additionalContext,
#      exits 0.
#
# Dedup file: ~/.thrum/var/hook-state/s-<session_id>/injected-rules, where session_id
# is stdin session_id, then CLAUDE_CODE_SESSION_ID, then CLAUDE_SESSION_ID.
# With neither, nothing is recorded.
# One rule ID per line. Created on first injection.
#
# Output contract (one JSON object on stdout, exit 0, nothing on stderr):
#   - Soft rules: hookSpecificOutput.additionalContext carries the rule text;
#     it lands in the model context as a system reminder.
#   - Hard rules: hookSpecificOutput.permissionDecision=deny with
#     permissionDecisionReason (the model sees it as the tool error), and the
#     rule text in additionalContext. Never "ask": it shows the reason to nobody.
#   - No match: no output.
#
# Plugin sync: this hook is wired in claude-plugin only. The build-time sync does
# not propagate hooks to opencode/codex/cursor plugins (they use different hook
# registration mechanisms). Manual step required per plugin when adopting.
#
# Smoke test: edit path/to/x.go → hard rule (safedb) fires deny.
#             Edit again → dedup prevents re-fire (no output for already-injected).

set -u
# Fail-open trap: any unexpected error defaults to allow so this hook
# never blocks the agent's ability to edit files. Guideline injection
# is a nicety; it must never wedge real work.
trap 'exit 0' ERR

# Require jq and thrum — bail silently if either is absent so the hook
# never blocks the agent on a misconfigured machine.
if ! command -v jq >/dev/null 2>&1 || ! command -v thrum >/dev/null 2>&1; then
    exit 0
fi

# Detect timeout command (macOS ships gtimeout via coreutils, not timeout).
_timeout_cmd=""
if command -v timeout >/dev/null 2>&1; then
    _timeout_cmd="timeout 7"
elif command -v gtimeout >/dev/null 2>&1; then
    _timeout_cmd="gtimeout 7"
fi

input=$(cat)

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool_name" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

# Extract file path(s).
file_paths=()
if [ "$tool_name" = "MultiEdit" ]; then
    while IFS= read -r p; do
        [ -n "$p" ] && file_paths+=("$p")
    done < <(printf '%s' "$input" | jq -r '.tool_input.edits[]?.file_path // empty' 2>/dev/null)
else
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -n "$fp" ] && file_paths+=("$fp")
fi

if [ ${#file_paths[@]} -eq 0 ]; then
    exit 0
fi

# Fetch agent_rule records (zoom=full).
rules_json=$(${_timeout_cmd} thrum memory list --kind agent_rule --zoom full --format json 2>/dev/null) || rules_json='{"items":[]}'

# Per-session dedup key: stdin session_id, then Claude environment fallback.
# Without either, deliver without recording. The folder is s-<id> with "/" mapped to "_", so no id
# can escape hook-state (a "..", "a/b" or "../x" id stays one folder inside it).
session_id=$(printf '%s' "$input" | jq -r --arg e "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}" 'if (.session_id // "") != "" then .session_id else $e end' 2>/dev/null) || session_id=""
dedup_file=/dev/null
if [ -n "$session_id" ]; then
    dedup_file="${HOME}/.thrum/var/hook-state/s-${session_id//\//_}/injected-rules"
    mkdir -p "${dedup_file%/*}" 2>/dev/null && touch "$dedup_file" 2>/dev/null || dedup_file=/dev/null
fi

# Match rules against file paths and tool.
matched_hard=()
matched_soft=()

rule_count=$(printf '%s' "$rules_json" | jq '.items | length' 2>/dev/null) || exit 0
[ -z "$rule_count" ] && exit 0

for i in $(seq 0 $((rule_count - 1))); do
    rule=$(printf '%s' "$rules_json" | jq ".items[$i]" 2>/dev/null) || continue
    rule_id=$(printf '%s' "$rule" | jq -r '.id // empty' 2>/dev/null) || continue
    metadata_raw=$(printf '%s' "$rule" | jq -r '.metadata // empty' 2>/dev/null) || continue

    # Parse triggers from metadata — metadata may be a JSON string or
    # already an object; try both before giving up.
    triggers=$(printf '%s' "$metadata_raw" | jq -r '.triggers // empty' 2>/dev/null || echo '')
    [ -z "$triggers" ] && continue
    # jq returns 'null' when the key exists but is null.
    [ "$triggers" = "null" ] && continue

    enforcement=$(printf '%s' "$triggers" | jq -r '.enforcement // "soft"' 2>/dev/null) || enforcement="soft"
    tools_json=$(printf '%s' "$triggers" | jq -c '.tools // []' 2>/dev/null) || tools_json='[]'
    globs_json=$(printf '%s' "$triggers" | jq -c '.path_globs // []' 2>/dev/null) || globs_json='[]'

    # Check tool match.
    tool_match=$(printf '%s' "$tools_json" | jq --arg t "$tool_name" 'map(select(. == $t)) | length > 0' 2>/dev/null) || continue
    [ "$tool_match" = "true" ] || continue

    # Check path glob match against any file path.
    glob_count=$(printf '%s' "$globs_json" | jq 'length' 2>/dev/null) || continue
    path_matched=false
    for fp in "${file_paths[@]}"; do
        for gi in $(seq 0 $((glob_count - 1))); do
            glob=$(printf '%s' "$globs_json" | jq -r ".[$gi]" 2>/dev/null) || continue
            # Use bash extglob-style [[ == ]] pattern matching.
            # shellcheck disable=SC2053
            if [[ "$fp" == $glob ]]; then
                path_matched=true
                break 2
            fi
        done
    done
    "$path_matched" || continue

    # Check dedup — skip rules already injected this session.
    if grep -qxF "$rule_id" "$dedup_file" 2>/dev/null; then
        continue
    fi

    body=$(printf '%s' "$rule" | jq -r '.body_full // .body_oneline // empty' 2>/dev/null) || continue
    title=$(printf '%s' "$rule" | jq -r '.title // empty' 2>/dev/null) || continue

    case "$enforcement" in
        hard) matched_hard+=("${rule_id}"$'\x01'"${title}"$'\x01'"${body}") ;;
        *)    matched_soft+=("${rule_id}"$'\x01'"${title}"$'\x01'"${body}") ;;
    esac
done

# Split a "rule_id\x01title\x01body" entry. Parameter expansion, not read: read
# stops at the first newline and would truncate a multi-line rule body.
split_entry() {
    rule_id=${1%%$'\x01'*}
    local rest=${1#*$'\x01'}
    title=${rest%%$'\x01'*}
    body=${rest#*$'\x01'}
}

# Soft rules: record each as injected and join the texts into one context string.
context=""
if [ "${#matched_soft[@]}" -gt 0 ]; then
    for entry in "${matched_soft[@]}"; do
        split_entry "$entry"
        printf '%s\n' "$rule_id" >> "$dedup_file"
        [ -n "$context" ] && context+=$'\n\n'
        context+="Agent Rule: ${title}"$'\n\n'"${body}"
    done
fi

# First hard rule (one per invocation; the rest fire on the retry): deny with the
# reason. Soft texts ride in the same single JSON object.
if [ ${#matched_hard[@]} -gt 0 ]; then
    split_entry "${matched_hard[0]}"
    printf '%s\n' "$rule_id" >> "$dedup_file"
    reason="Agent rule (enforcement=hard): ${title} -- ${body}"
    [ -n "$context" ] && context+=$'\n\n'
    context+="Agent Rule: ${title}"$'\n\n'"${body}"
    # Each text is encoded as a JSON string on stdin (no NUL, so no reliance on jq -R
    # NUL handling); argv is capped at 128 KiB per argument.
    if output=$({ printf '%s' "$reason" | jq -Rs .; printf '%s' "$context" | jq -Rs .; } 2>/dev/null | jq -n 'input as $r | input as $c | {hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r, additionalContext:$c}}' 2>/dev/null); then
        printf '%s\n' "$output"
        exit 0
    fi
    # jq failed — emit the deny anyway with a best-effort string (control chars stripped).
    safe_reason=$(printf '%s' "$reason" | tr '\000-\037' ' ' | tr '"' "'" | tr '\\' '/')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$safe_reason"
    exit 0
fi

# Soft rules only: one JSON object carrying the joined rule text.
if [ -n "$context" ]; then
    printf '%s' "$context" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:.}}' 2>/dev/null
fi
exit 0
