#!/bin/bash
# Stop-hook helper: queue ONE nudge to a tmux-managed agent's own pane instead
# of blocking the stop. `thrum tmux send` is the daemon's queued send: it waits
# for the pane to go idle (and types after a bounded wait even if the pane never
# looks idle), types the text and withholds Enter only on a detected dialog.
# Always exits 0 and prints nothing on stdout, so the runtime never renders it
# as Stop feedback.
#
# The nudge is queued at stop time but delivered later. The helper re-runs the
# hook's unread count and sends ONLY if something is still unread; the text
# carries that count. It does NOT gate on the pane being observable or ready:
# an idle pane shows no new activity, so such a gate would drop the nudge.
#
# Rate limit: one marker file per agent, <var_dir>/stop-nudge-marker-<agent_id>,
# holding "<sha256 of the sorted unread message ids> <epoch seconds written>".
# The same unread set nudges at most once per 1800 s; a changed set, an expired
# marker, or a missing/unreadable/malformed marker nudges. The marker is
# rewritten (temp file + mv in the same dir, so there is only ever one file)
# after the send was issued: rc 0, or rc 3/4 (typed but Enter withheld / verdict
# unknown; retyping would duplicate the text). A failed send (any other rc)
# writes nothing, so the next stop retries.
# A shrink of the unread set (some read, some still unread) is a different set and
# nudges again by design. Agent ids that collide after the character substitution
# can only share a marker: worst case one suppressed or one extra nudge.
# THRUM_STOP_NUDGE_NOW (epoch seconds) overrides the clock; TEST SEAM ONLY (a
# frozen value would keep a marker fresh forever, so production never sets it).
#
# Usage: stop-nudge-pane.sh <agent_id> <unread_count> [project_dir] [tmux_session] [var_dir]
agent_id="${1:-}"
count="${2:-0}"
project_dir="${3:-.}"
# $4 (tmux session) is accepted for call-site compatibility but unused: the send targets the agent id.
var_dir="${5:-}"
[ -n "$agent_id" ] || exit 0
# agent_id may be <name>@<daemon_id>; the tmux send target and the marker file use the bare name.
agent_name="${agent_id%%@*}"
NUDGE_WINDOW_SECS=1800
build_text() {
  text="ACTION REQUIRED: You have $count unread message(s). Run \`thrum inbox --unread\` now to read and respond to them. Then mark them read: \`thrum message read <id> [<id>...]\` for the ids shown, or \`thrum message read --all\` (dry run) followed by \`thrum message read --all --force\` to clear everything — so this hook doesn't fire again on old messages."
}
sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  else return 1; fi
}
now_epoch() {
  case "${THRUM_STOP_NUDGE_NOW:-}" in
    ''|*[!0-9]*) date +%s ;;
    *) printf '%s' "$THRUM_STOP_NUDGE_NOW" ;;
  esac
}
# marker_path: sets marker/set_hash/now from the fresh inbox JSON; returns 1 when
# no usable marker is possible (then the nudge is always sent and nothing is written).
marker_setup() {
  local ids safe
  [ -n "$var_dir" ] || return 1
  ids=$(printf '%s' "$1" | jq -r '[.messages[]? | select(.is_read != true) | .message_id // empty] | sort | .[]' 2>/dev/null) || return 1
  [ -n "$ids" ] || return 1
  if [ "$(printf '%s' "$1" | jq -r '.has_more // false' 2>/dev/null)" = true ]; then
    ids="$ids"$'\n'"+more:$2"
  fi
  set_hash=$(sha256_text "$ids") || return 1
  [ -n "$set_hash" ] || return 1
  safe=$(printf '%s' "$agent_name" | tr -c 'A-Za-z0-9_.-' '_')
  marker="$var_dir/stop-nudge-marker-$safe"
  now=$(now_epoch)
}
# marker_suppresses: true when the marker names this set and is under the window.
marker_suppresses() {
  local mhash mts extra
  [ -f "$marker" ] || return 1
  { read -r mhash mts extra <"$marker"; } 2>/dev/null || return 1
  [ -z "$extra" ] || return 1
  case "$mhash" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#mhash}" -eq 64 ] || return 1
  case "$mts" in ''|*[!0-9]*) return 1 ;; esac
  [ "$mhash" = "$set_hash" ] || return 1
  [ "$mts" -le "$now" ] || return 1
  [ $((now - mts)) -lt "$NUDGE_WINDOW_SECS" ]
}
marker_write() {
  local tmp
  [ ! -d "$marker" ] || return 0
  mkdir -p "$var_dir" 2>/dev/null || return 0
  tmp=$(mktemp "$var_dir/.stop-nudge-marker.XXXXXX" 2>/dev/null) || return 0
  if printf '%s %s\n' "$set_hash" "$now" >"$tmp" 2>/dev/null && mv -f "$tmp" "$marker" 2>/dev/null; then
    :
  else
    rm -f "$tmp"
  fi
}
send_nudge() {
  local rc=0 inbox fresh marker="" set_hash="" now=""
  command -v jq >/dev/null 2>&1 || return 0
  inbox=$(cd "$project_dir" 2>/dev/null && THRUM_AGENT_ID="$agent_id" thrum inbox --unread --json 2>/dev/null) || return 0
  fresh=$(printf '%s' "$inbox" | jq -r '.unread // 0' 2>/dev/null) || return 0
  case "$fresh" in ''|*[!0-9]*) return 0 ;; esac
  [ "$fresh" -gt 0 ] || return 0
  count="$fresh"
  if marker_setup "$inbox" "$fresh"; then
    if marker_suppresses; then return 0; fi
  else
    marker=""
  fi
  build_text
  (cd "$project_dir" 2>/dev/null; THRUM_AGENT_ID="$agent_id" thrum tmux send "$agent_name" "$text" >/dev/null 2>&1) || rc=$?
  case "$rc" in
    0|3|4) [ -z "$marker" ] || marker_write ;;
    *) echo "thrum stop-nudge-pane.sh: tmux send rc=${rc} for ${agent_name}; nudge not delivered" >&2 ;;
  esac
}
# The daemon's queued send waits for the pane to go idle, which cannot happen
# while this Stop hook is still running, so detach it and return at once.
# THRUM_STOP_NUDGE_SYNC=1 runs it inline (tests).
if [ "${THRUM_STOP_NUDGE_SYNC:-0}" = 1 ]; then
  send_nudge
else
  send_nudge >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true
fi
exit 0
