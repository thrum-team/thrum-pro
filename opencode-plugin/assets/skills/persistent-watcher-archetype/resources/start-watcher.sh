#!/usr/bin/env bash
# start-watcher.sh - the one supported way to start a watcher or steward.
#
# A coordinator runs this once per watcher/steward. It checks everything
# first and creates nothing when any check fails, then uses existing thrum
# commands in a fixed order: worktree create, write watch_params.json,
# tmux create, tmux launch, monitor start. The pane-watch monitor's ticks wake
# the agent; its params file exists before the first tick.
#
# Usage:
#   start-watcher.sh <name> --role watcher|steward --parent <agent|user:NAME> \
#     --roster <a,b,...|@file> --model <model> --effort <effort> \
#     [--cadence-active 5m] [--cadence-idle 10m] [--runtime <runtime>] \
#     [--owner <user>] [--restart-ctx-pct 50]
#
#   --roster   comma-separated agent names, or @file holding one name per
#              line or a JSON array. An array entry may be a name or an
#              object {"agent_id","hostname","tmux_session"} for an agent on
#              another machine.
#   --cadence  durations such as 90s, 5m, 2h. Anything under one minute is
#              refused (the monitor schedule has a one-minute floor).
#   --owner    the human who receives escalations, as a thrum user name.
#              Without it the owner is the first @user: entry of
#              permission_supervisors in .thrum/config.json. No owner is a
#              refusal. Whether the owner has linked Telegram or email is not
#              consulted: the owner is sent a normal message to their inbox,
#              and the existing bridges forward it if they are linked.
#
# Environment (for tests): THRUM_BIN (default thrum), THRUM_DIR (the
# redirect-resolved .thrum directory).
#
# Exit status: 0 started and verified; 2 refused before creating anything;
# 1 a step failed after creation began. A failure removes what this run
# created (monitor, tmux session, agent registration, params directory,
# worktree), tracked by recorded path; anything that existed before the run is
# never touched. If a removal itself fails, the script says what was left.
set -uo pipefail

THRUM="${THRUM_BIN:-thrum}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TEMPLATE="${SCRIPT_DIR}/watch_params.template.json"
MATCH_REGEX='^watch-tick: (cycle done|RESOLUTION-FAIL)'

die() {
  printf 'start-watcher: %s\n' "$1" >&2
  exit "${2:-2}"
}

NAME=""
ROLE=""
PARENT=""
ROSTER_ARG=""
CAD_ACTIVE="5m"
CAD_IDLE="10m"
RUNTIME=""
MODEL=""
EFFORT=""
OWNER_ARG=""
RESTART_PCT=50

while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) ROLE="${2-}"; shift 2 ;;
    --parent) PARENT="${2-}"; shift 2 ;;
    --roster) ROSTER_ARG="${2-}"; shift 2 ;;
    --cadence-active) CAD_ACTIVE="${2-}"; shift 2 ;;
    --cadence-idle) CAD_IDLE="${2-}"; shift 2 ;;
    --runtime) RUNTIME="${2-}"; shift 2 ;;
    --model) MODEL="${2-}"; shift 2 ;;
    --effort) EFFORT="${2-}"; shift 2 ;;
    --owner) OWNER_ARG="${2-}"; shift 2 ;;
    --restart-ctx-pct) RESTART_PCT="${2-}"; shift 2 ;;
    -h | --help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *)
      [ -z "${NAME}" ] || die "unexpected argument: $1"
      NAME="$1"
      shift
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "${TEMPLATE}" ] || die "missing ${TEMPLATE}"

# --- validate everything before touching anything --------------------------
printf '%s' "${NAME}" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*$' || die "name must be letters, digits and underscores, starting with a letter"
case "${ROLE}" in watcher | steward) ;; *) die "--role must be watcher or steward" ;; esac
[ -n "${PARENT}" ] || die "--parent is required"
[ -n "${MODEL}" ] || die "--model is required (every launch pins a model)"
[ -n "${EFFORT}" ] || die "--effort is required (every launch pins an effort)"
printf '%s' "${RESTART_PCT}" | grep -Eq '^[0-9]+$' || die "--restart-ctx-pct must be an integer"

# cadence_secs <duration>: print seconds, or return 1.
cadence_secs() {
  local n unit
  printf '%s' "$1" | grep -Eq '^[0-9]+[smh]$' || return 1
  n="${1%[smh]}"
  unit="${1#"${n}"}"
  case "${unit}" in
    s) printf '%s' "${n}" ;;
    m) printf '%s' "$((n * 60))" ;;
    h) printf '%s' "$((n * 3600))" ;;
  esac
}
ACTIVE_SECS="$(cadence_secs "${CAD_ACTIVE}")" || die "--cadence-active '${CAD_ACTIVE}' is not a duration like 5m"
IDLE_SECS="$(cadence_secs "${CAD_IDLE}")" || die "--cadence-idle '${CAD_IDLE}' is not a duration like 10m"
[ "${ACTIVE_SECS}" -ge 60 ] || die "--cadence-active '${CAD_ACTIVE}' is below one minute"
[ "${IDLE_SECS}" -ge 60 ] || die "--cadence-idle '${CAD_IDLE}' is below one minute"

# cron_for <seconds>: the 5-field schedule for the idle cadence.
cron_for() {
  local mins
  mins=$(($1 / 60))
  if [ "${mins}" -lt 60 ]; then
    printf '*/%s * * * *' "${mins}"
  elif [ $((mins % 60)) -eq 0 ] && [ $((mins / 60)) -le 23 ]; then
    printf '0 */%s * * *' "$((mins / 60))"
  else
    return 1
  fi
}
CRON="$(cron_for "${IDLE_SECS}")" || die "--cadence-idle '${CAD_IDLE}' must be under an hour or a whole number of hours up to 23"

# Roster: names or objects, never empty.
[ -n "${ROSTER_ARG}" ] || die "--roster is required and must not be empty"
case "${ROSTER_ARG}" in
  @*)
    [ -f "${ROSTER_ARG#@}" ] || die "roster file ${ROSTER_ARG#@} not found"
    RAW_ROSTER="$(cat "${ROSTER_ARG#@}")"
    ;;
  *) RAW_ROSTER="${ROSTER_ARG}" ;;
esac
if printf '%s' "${RAW_ROSTER}" | grep -Eq '^[[:space:]]*\['; then
  ROSTER_JSON="$(printf '%s' "${RAW_ROSTER}" | jq -c '.' 2>/dev/null)" || die "roster is not valid JSON"
else
  ROSTER_JSON="$(printf '%s\n' "${RAW_ROSTER}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | { grep -v '^$' || true; } | jq -R . | jq -cs '.')" || die "roster could not be parsed"
fi
[ "$(printf '%s' "${ROSTER_JSON}" | jq 'length')" -gt 0 ] || die "roster is empty; a watcher with no roster has nothing to watch"
printf '%s' "${ROSTER_JSON}" | jq -e 'all(.[]; (type == "string" and length > 0) or (type == "object" and (.agent_id // "") != "" and (.hostname // "") != "" and (.tmux_session // "") != ""))' >/dev/null ||
  die "every roster entry must be an agent name or an object with agent_id, hostname and tmux_session"

# The team: the name must be free, the parent and every local member known.
TEAM_JSON="$("${THRUM}" team --json 2>/dev/null)" || die "could not read the team (thrum team --json failed)"
# This daemon's own ID: `daemon_id` from `thrum whoami --json`, read once here for every member_exists call below.
# Absent (an old-form daemon) it stays empty: no row is qualified and every row is local.
OWN_DAEMON_ID="$("${THRUM}" whoami --json </dev/null 2>/dev/null | jq -r '.daemon_id // ""' 2>/dev/null)" || OWN_DAEMON_ID=""
# A team row with is_local false whose id names this daemon: the flag wins (the row is not local); one stderr line
# per such row, once per run.
[ -z "${OWN_DAEMON_ID}" ] || printf '%s' "${TEAM_JSON}" | jq -r --arg own "${OWN_DAEMON_ID}" '.team.members[]? | select(.is_local == false) | (.agent_id // "") | select(endswith("@" + $own))' 2>/dev/null |
  while IFS= read -r w; do printf "team row '%s' has is_local false but names this daemon\n" "${w}" >&2; done
# member_exists <entry> [local]: 0 when the entry resolves to exactly one team member. A full ID (has "@") matches
# the row whose agent_id equals it (a row with no "@" counts as <id>@<this daemon> when that ID is known) and
# nothing else. A bare name means this daemon's agent first (a row that carries a boolean is_local is local exactly
# when it says so; without one it is local when its agent_id has no "@" or its daemon half is this daemon), matched on .name when non-empty, else the id up to "@"; a bare
# row `a` and a row `a@<this daemon>` are one agent. With no local match the single other row of that name is the
# member. Several candidate IDs resolve to nothing: one stderr line names them and the callers take their
# existing "does not resolve" / not-registered path. The "local" argument looks at this daemon's rows only (the
# watcher's own name: an agent of that name on another daemon neither blocks nor is ambiguous).
member_exists() {
  local res
  res="$(printf '%s' "${TEAM_JSON}" | jq -r --arg r "$1" --arg own "${OWN_DAEMON_ID}" --arg loc "${2-}" '
    [.team.members[]? | (.agent_id // "") as $id
      | {id: $id,
         name: ((.name // "" | select(. != "")) // ($id | split("@")[0])),
         lcl: (if (.is_local | type) == "boolean" then .is_local else ((($id | contains("@")) | not) or ($own != "" and ($id | endswith("@" + $own)))) end)}
      | .nid = (if ($id | contains("@")) or $own == "" or (.lcl | not) then $id else $id + "@" + $own end)] as $m
    | if ($r | contains("@")) then
        (if any($m[]; .id == $r or .nid == $r) then "match" else "none" end)
      else
        ([$m[] | select(.name == $r)]) as $c
        | ([$c[] | select(.lcl) | .nid] | unique) as $l
        | (if $loc == "local" then [] else [$c[] | select(.lcl | not) | .nid] | unique end) as $x
        | if ($l | length) == 1 then "match"
          elif ($l | length) > 1 then "ambiguous " + ($l | join(" "))
          elif ($x | length) == 1 then "match"
          elif ($x | length) > 1 then "ambiguous " + ($x | join(" "))
          else "none" end
      end' 2>/dev/null)" || return 1
  case "${res}" in
    match) return 0 ;;
    ambiguous*)
      printf "ambiguous roster entry '%s': candidates %s\n" "$1" "${res#ambiguous }" >&2
      return 1
      ;;
    *) return 1 ;;
  esac
}
member_exists "${NAME}" local && die "${NAME} is already registered"
case "${PARENT}" in
  user:*) ;;
  *) member_exists "${PARENT}" || die "--parent ${PARENT} does not resolve in thrum team" ;;
esac
while IFS= read -r m; do
  [ -z "${m}" ] || member_exists "${m}" || die "roster member ${m} does not resolve in thrum team"
done <<<"$(printf '%s' "${ROSTER_JSON}" | jq -r '.[] | select(type == "string")')"
ROSTER_NAMES="$(printf '%s' "${ROSTER_JSON}" | jq -r '.[] | if type == "object" then .agent_id else . end')"

# --- owner -----------------------------------------------------------------
if [ -n "${THRUM_DIR:-}" ]; then
  T="${THRUM_DIR}"
else
  TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository (set THRUM_DIR)"
  T="$(cat "${TOP}/.thrum/redirect" 2>/dev/null)"
  [ -n "${T}" ] || T="${TOP}/.thrum"
fi
[ -d "${T}" ] || die "no .thrum directory at ${T}"

norm_user() { printf '%s' "$1" | sed 's/^@//; s/^user://'; }

if [ -n "${OWNER_ARG}" ]; then
  OWNER="$(norm_user "${OWNER_ARG}")"
else
  OWNER="$(norm_user "$(jq -r '.permission_supervisors[]? | select(startswith("@user:"))' "${T}/config.json" 2>/dev/null | head -1)")"
fi
[ -n "${OWNER}" ] || die "no owner: pass --owner or set a @user: entry in permission_supervisors"

# --- start, in order -------------------------------------------------------
AGENT_DIR="${T}/agents/${NAME}"
PARAMS="${AGENT_DIR}/watch_params.json"
[ ! -e "${AGENT_DIR}" ] || die "${AGENT_DIR} already exists; remove it or pick another name"

# What this run created, recorded so a failure removes only that.
MADE_WT=""
MADE_AGENT_DIR=""
MADE_SESSION=""
MADE_MONITOR=""

# cleanup_created: remove what this run created, newest first. Never forces,
# never touches a path this run did not record.
cleanup_created() {
  if [ -n "${MADE_MONITOR}" ]; then
    "${THRUM}" monitor delete "${NAME}-pane-watch" >/dev/null 2>&1 ||
      printf 'start-watcher: could not delete monitor %s-pane-watch; it is still registered\n' "${NAME}" >&2
  fi
  if [ -n "${MADE_SESSION}" ]; then
    "${THRUM}" tmux kill "${NAME}" >/dev/null 2>&1 ||
      printf 'start-watcher: could not kill tmux session %s; it is still there\n' "${NAME}" >&2
    "${THRUM}" agent delete "${NAME}" >/dev/null 2>&1 ||
      printf 'start-watcher: could not delete agent %s; it is still registered\n' "${NAME}" >&2
  fi
  if [ -n "${MADE_AGENT_DIR}" ]; then
    rm -r -- "${MADE_AGENT_DIR:?}" ||
      printf 'start-watcher: could not remove %s; it is still there\n' "${MADE_AGENT_DIR}" >&2
  fi
  if [ -n "${MADE_WT}" ]; then
    # worktree teardown is the inverse of worktree create: it refuses a live
    # agent's home, never forces, and salvages file content before removal.
    "${THRUM}" worktree teardown "${MADE_WT}" >/dev/null 2>&1 ||
      printf 'start-watcher: could not remove worktree %s; it is still there\n' "${MADE_WT}" >&2
  fi
}

# fail <message>: clean up what this run created, then exit 1.
fail() {
  printf 'start-watcher: %s\n' "$1" >&2
  cleanup_created
  exit 1
}

WT_JSON="$("${THRUM}" worktree create "${NAME}" --json)" || die "worktree create failed; nothing else was started" 1
WT_PATH="$(printf '%s' "${WT_JSON}" | jq -r '.worktree_path // empty')"
[ -n "${WT_PATH}" ] || die "worktree create printed no worktree_path; nothing else was started" 1
MADE_WT="${WT_PATH}"

EXPECTED="$(jq --arg n "${NAME}" --arg p "${PARENT}" --arg m "${MODEL}" --argjson r "${ROSTER_JSON}" \
  --arg ca "${CAD_ACTIVE}" --arg ci "${CAD_IDLE}" --argjson pct "${RESTART_PCT}" \
  '.watcher = $n | .parent = $p | .model = $m | .roster = $r | .cadence_active = $ca | .cadence_idle = $ci | .restart_ctx_pct = $pct' "${TEMPLATE}")" ||
  fail "could not fill the params template"
mkdir -p "${AGENT_DIR}" || fail "could not create ${AGENT_DIR}"
MADE_AGENT_DIR="${AGENT_DIR}"
if ! { printf '%s\n' "${EXPECTED}" >"${PARAMS}.tmp" && mv "${PARAMS}.tmp" "${PARAMS}"; }; then
  fail "could not write ${PARAMS}"
fi
[ "$(jq -S . "${PARAMS}")" = "$(printf '%s' "${EXPECTED}" | jq -S .)" ] || fail "${PARAMS} did not re-read equal"

RT_ARGS=()
[ -z "${RUNTIME}" ] || RT_ARGS=(--runtime "${RUNTIME}")
MADE_SESSION=1
"${THRUM}" tmux create "${NAME}" --name "${NAME}" --role "${ROLE}" --module "${ROLE}" --cwd "${WT_PATH}" --model "${MODEL}" --effort "${EFFORT}" ${RT_ARGS[@]+"${RT_ARGS[@]}"} ||
  fail "tmux create failed"
"${THRUM}" tmux launch "${NAME}" --model "${MODEL}" --effort "${EFFORT}" ${RT_ARGS[@]+"${RT_ARGS[@]}"} ||
  fail "tmux launch failed; the agent did not start"

for f in thrum-watch-pane-capture.sh thrum-capture-fallback.sh; do
  if ! { cp "${SCRIPT_DIR}/${f}" "${AGENT_DIR}/${f}" && chmod +x "${AGENT_DIR}/${f}"; }; then
    fail "could not copy ${f} into ${AGENT_DIR}"
  fi
done
"${THRUM}" monitor start --name "${NAME}-pane-watch" --match "${MATCH_REGEX}" --to "@${NAME}" --notify-on-success \
  --schedule "${CRON}" -- "${AGENT_DIR}/thrum-watch-pane-capture.sh" ||
  fail "monitor start failed"
MADE_MONITOR=1

if [ "${ROLE}" = "steward" ]; then
  while IFS= read -r m; do
    [ -n "${m}" ] || continue
    "${THRUM}" send --to "@${m}" --stdin <<EOF || printf 'start-watcher: warning: could not brief %s\n' "${m}" >&2
steward: @${NAME}
Send questions that need the owner to @${NAME} as "NEED [topic]: <what you need decided and why>". The steward routes them to the owner and replies with the owner's answer. See the brainstorm-queue-aware skill for the convention.
EOF
  done <<<"${ROSTER_NAMES}"
fi

# --- verify by effect ------------------------------------------------------
"${THRUM}" monitor list --json 2>/dev/null | jq -e --arg n "${NAME}-pane-watch" 'any(.[]?; .name == $n)' >/dev/null ||
  fail "monitor ${NAME}-pane-watch is not listed after start"

printf 'started %s (%s)\n' "${NAME}" "${ROLE}"
printf '  roster:  %s\n' "$(printf '%s' "${ROSTER_NAMES}" | tr '\n' ' ')"
printf '  parent:  %s\n' "${PARENT}"
printf '  cadence: active %s, idle %s (schedule %s)\n' "${CAD_ACTIVE}" "${CAD_IDLE}" "${CRON}"
printf '  params:  %s\n' "${PARAMS}"
printf '  owner:   @user:%s\n' "${OWNER}"
exit 0
