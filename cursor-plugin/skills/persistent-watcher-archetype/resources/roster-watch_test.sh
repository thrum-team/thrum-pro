#!/usr/bin/env bash
# roster-watch_test.sh — unit tests for roster-watch.sh's
# resolve_watch_params() (the ".thrum/redirect" fix), plus a
# coverage bonus for thrum-watch-pane-capture.sh's PARAMS_FILE resolution
# logic (inline harness — that script isn't structured as sourceable
# functions the way roster-watch.sh is; see Scenario 3 below).
#
# Run: bash claude-plugin/skills/persistent-watcher-archetype/resources/roster-watch_test.sh
# (or: SCRIPT_UNDER_TEST=/path/to/alt-roster-watch.sh bash roster-watch_test.sh
#  to run Scenario 1 against a different implementation, e.g. for a manual
#  RED-before/GREEN-after check against a deliberately-reverted copy.)
#
# All tests are hermetic: every fixture is a throwaway tree under mktemp -d,
# cleaned up via a trap; nothing here touches the real repo's .thrum, a live
# daemon, or the network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$SCRIPT_DIR/roster-watch.sh}"

# shellcheck source=/dev/null
source "$SCRIPT_UNDER_TEST" || {
  echo "roster-watch.sh not found/sourceable at $SCRIPT_UNDER_TEST -- resolve_watch_params is missing" >&2
  exit 1
}

pass=0
fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "PASS: $desc"; pass=$((pass + 1));
  else echo "FAIL: $desc -- expected '$expected' got '$actual'"; fail=$((fail + 1)); fi
}
assert_ne() {
  local desc="$1" unexpected="$2" actual="$3"
  if [ "$unexpected" != "$actual" ]; then echo "PASS: $desc"; pass=$((pass + 1));
  else echo "FAIL: $desc -- '$actual' unexpectedly equals '$unexpected'"; fail=$((fail + 1)); fi
}

# roster_count <file> -- number of entries in the "roster" array of a
# watch_params.json fixture. Uses python3 (already a hard dependency of
# roster-watch.sh itself, e.g. load_roster()).
roster_count() {
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(len(d.get("roster", [])))
except Exception:
    print(-1)
' "$1" 2>/dev/null
}

# mk_watch_params <file> <n> -- write a watch_params.json fixture with a
# roster array of n plain-string entries.
mk_watch_params() {
  local file="$1" n="$2"
  mkdir -p "$(dirname "$file")"
  python3 -c '
import json, sys
n = int(sys.argv[1])
json.dump({"roster": [f"agent{i}" for i in range(n)]}, open(sys.argv[2], "w"))
' "$n" "$file"
}

AGENT="watcher_primary"

# =============================================================================
# Scenario 1 (MANDATORY, cmain-required regression guard): a worktree that
# redirects to a main-repo tree. The "roster-editing agent's Edit-tool write"
# lands in the REDIRECT TARGET (main-repo) copy -- that's the physically
# correct, shared, redirect-resolved location per the AgentDir path helper
# ("the agents/ tree is shared, not per-worktree"), and it's what
# resolve_watch_params must read. A worktree-LOCAL copy at the naive,
# unresolved path is a decoy: it's what a broken script (SCRIPT_DIR-relative,
# no redirect-follow) would read instead, and it must be ignored.
#
# Bead framing: main-repo (correct) copy has 25 entries ("not 25" in the
# bug's own words -- i.e. the FIXED behavior must see 25); the worktree-local
# decoy has 24 (the stale/wrong count an unfixed script would see instead).
# =============================================================================
echo "--- Scenario 1: regression guard (redirect-resolved read wins over worktree-local decoy) ---"

worktree_root="$(mktemp -d)"
mainrepo_root="$(mktemp -d)"
trap 'rm -r -- "$worktree_root" "$mainrepo_root" 2>/dev/null || true' EXIT

mkdir -p "$worktree_root/.thrum"
printf '%s/.thrum' "$mainrepo_root" > "$worktree_root/.thrum/redirect"

mainrepo_params="$mainrepo_root/.thrum/agents/$AGENT/watch_params.json"
worktree_decoy_params="$worktree_root/.thrum/agents/$AGENT/watch_params.json"

mk_watch_params "$mainrepo_params" 25       # the real edit, correctly-wired fixture
mk_watch_params "$worktree_decoy_params" 24 # the stale worktree-local decoy

resolved="$(resolve_watch_params "$worktree_root" "$AGENT")"
assert_eq "resolves to the redirect-target (main-repo) path" "$mainrepo_params" "$resolved"
assert_ne "does NOT resolve to the worktree-local decoy path" "$worktree_decoy_params" "$resolved"
assert_eq "resolved file has the EDITED count (25, not 24)" "25" "$(roster_count "$resolved")"

# --- Negative control: prove the resolver is really reading the redirect
# target's CONTENT, not something incidental (e.g. a hardcoded/dead-end
# path, or a test bug where both fixtures happen to satisfy the assertion
# regardless of which tree holds what). Swap which tree holds the "right"
# (25) vs "wrong" (24) count, WITHOUT changing which path resolve_watch_params
# points at. If the resolver is doing real redirect-following, the resolved
# PATH stays the main-repo path (structural, content-independent), but the
# roster COUNT read from it must now be 24 (the swapped-in wrong count) --
# i.e. the same "expect 25" assertion used above must now correctly FAIL,
# proving the earlier PASS wasn't vacuous.
echo "--- Scenario 1 (mis-wired control): swapped fixture must make the same assertion fail ---"
mk_watch_params "$mainrepo_params" 24        # now the main-repo copy is "stale"
mk_watch_params "$worktree_decoy_params" 25  # decoy now happens to hold the "right" count

resolved_mis="$(resolve_watch_params "$worktree_root" "$AGENT")"
assert_eq "mis-wired: resolved path is unchanged (still the main-repo path)" "$mainrepo_params" "$resolved_mis"
got_count="$(roster_count "$resolved_mis")"
if [ "$got_count" = "25" ]; then
  echo "FAIL: mis-wired control -- expected count MISMATCH (resolver should read the swapped-in 24, not the decoy's 25) but got 25; this would mean the test passes regardless of fixture wiring"
  fail=$((fail + 1))
else
  echo "PASS: mis-wired control -- resolver reads 24 (the main-repo tree's current content), confirming it is not incidentally reading the decoy"
  pass=$((pass + 1))
fi

# restore correct wiring for anything downstream that might reuse these dirs
mk_watch_params "$mainrepo_params" 25
mk_watch_params "$worktree_decoy_params" 24

rm -r -- "$worktree_root" "$mainrepo_root"
trap - EXIT

# =============================================================================
# Scenario 2: existing (non-worktree) behavior unchanged -- no .thrum/redirect
# file at all means this IS the main repo; resolve_watch_params must fall
# through to the LOCAL .thrum/agents/<agent>/watch_params.json.
# =============================================================================
echo "--- Scenario 2: no redirect file -> resolves to local .thrum path (no regression) ---"

mainrepo_only="$(mktemp -d)"
trap 'rm -r -- "$mainrepo_only" 2>/dev/null || true' EXIT

local_params="$mainrepo_only/.thrum/agents/$AGENT/watch_params.json"
mk_watch_params "$local_params" 7
# deliberately no redirect file created

resolved_local="$(resolve_watch_params "$mainrepo_only" "$AGENT")"
assert_eq "no-redirect case resolves to the local path" "$local_params" "$resolved_local"
assert_eq "no-redirect case reads the local file's real content" "7" "$(roster_count "$resolved_local")"

rm -r -- "$mainrepo_only"
trap - EXIT

# =============================================================================
# Scenario 3 (bonus): thrum-watch-pane-capture.sh's PARAMS_FILE resolution.
# That script is NOT structured as sourceable functions (its redirect logic
# is a flat sequence of top-level assignments between REPO_ROOT and
# FALLBACK_SCRIPT, guarded by no function boundary) -- sourcing the whole
# file would run its lock-dir/roster-load/capture logic as a side effect.
# So this reproduces JUST that resolution snippet as a tiny inline harness,
# verified byte-for-byte against the live file below (so the harness can't
# silently drift from the real script) before asserting on it.
# =============================================================================
echo "--- Scenario 3 (bonus): thrum-watch-pane-capture.sh PARAMS_FILE resolution (inline harness) ---"

pane_capture_script="$SCRIPT_DIR/thrum-watch-pane-capture.sh"
if [ ! -f "$pane_capture_script" ]; then
  echo "SKIP: $pane_capture_script not found -- skipping Scenario 3"
else
  expected_snippet='THRUM_DIR="${REPO_ROOT}/.thrum"
if [ -f "${THRUM_DIR}/redirect" ]; then
  THRUM_DIR="$(tr -d '"'"'[:space:]'"'"' < "${THRUM_DIR}/redirect")"
fi
PARAMS_FILE="${THRUM_DIR}/agents/${AGENT_NAME}/watch_params.json"'
  live_snippet="$(sed -n '/^THRUM_DIR="\${REPO_ROOT}\/\.thrum"$/,/^PARAMS_FILE=/p' "$pane_capture_script")"
  if [ "$live_snippet" != "$expected_snippet" ]; then
    echo "FAIL: Scenario 3 harness has drifted from the live PARAMS_FILE resolution snippet in $pane_capture_script -- update the harness (this is a test-maintenance guard, not a product assertion)"
    echo "  live snippet was:"
    echo "$live_snippet" | sed 's/^/    /'
    fail=$((fail + 1))
  else
    echo "PASS: inline harness matches the live PARAMS_FILE resolution snippet verbatim"
    pass=$((pass + 1))

    resolve_pane_capture_params() {
      # Args: repo_root, agent_name. Mirrors the verbatim snippet above.
      local REPO_ROOT="$1" AGENT_NAME="$2" THRUM_DIR
      THRUM_DIR="${REPO_ROOT}/.thrum"
      if [ -f "${THRUM_DIR}/redirect" ]; then
        THRUM_DIR="$(tr -d '[:space:]' < "${THRUM_DIR}/redirect")"
      fi
      printf '%s/agents/%s/watch_params.json\n' "${THRUM_DIR}" "${AGENT_NAME}"
    }

    pc_worktree="$(mktemp -d)"
    pc_mainrepo="$(mktemp -d)"
    trap 'rm -r -- "$pc_worktree" "$pc_mainrepo" 2>/dev/null || true' EXIT

    mkdir -p "$pc_worktree/.thrum"
    printf '%s/.thrum' "$pc_mainrepo" > "$pc_worktree/.thrum/redirect"
    pc_mainrepo_params="$pc_mainrepo/.thrum/agents/$AGENT/watch_params.json"
    pc_decoy_params="$pc_worktree/.thrum/agents/$AGENT/watch_params.json"
    mk_watch_params "$pc_mainrepo_params" 25
    mk_watch_params "$pc_decoy_params" 24

    pc_resolved="$(resolve_pane_capture_params "$pc_worktree" "$AGENT")"
    assert_eq "pane-capture: redirect present -> resolves to main-repo path" "$pc_mainrepo_params" "$pc_resolved"
    assert_ne "pane-capture: does NOT resolve to worktree-local decoy" "$pc_decoy_params" "$pc_resolved"
    assert_eq "pane-capture: resolved file has the edited count (25)" "25" "$(roster_count "$pc_resolved")"

    rm -r -- "$pc_worktree" "$pc_mainrepo"
    trap - EXIT

    pc_mainrepo_only="$(mktemp -d)"
    trap 'rm -r -- "$pc_mainrepo_only" 2>/dev/null || true' EXIT
    pc_local_params="$pc_mainrepo_only/.thrum/agents/$AGENT/watch_params.json"
    mk_watch_params "$pc_local_params" 3
    pc_resolved_local="$(resolve_pane_capture_params "$pc_mainrepo_only" "$AGENT")"
    assert_eq "pane-capture: no redirect -> resolves to local path" "$pc_local_params" "$pc_resolved_local"
    rm -r -- "$pc_mainrepo_only"
    trap - EXIT
  fi
fi

# ---------------------------------------------------------------------------
# Scenario 4: load_roster's capture_daemon_overrides field.
# Regression guard for a REAL bug caught during that scrub: the plain-string
# roster-entry branch of load_roster's python emitter originally printed
# only 3 `|` separators (agent|||override) for what is now a 5-FIELD
# schema (agent|host|tmux|runtime|override, needing 4 separators) -- the
# missing separator silently shifted every subsequent field left by one,
# so a string-roster-entry agent's override always read back empty even
# when set. Covers both roster-entry shapes (plain string and the
# {agent_id,hostname,tmux_session} dict form) so a similar off-by-one in
# either emitter branch fails loud here instead of silently dropping an
# agent's --daemon-id routing in production.
# ---------------------------------------------------------------------------
echo "--- Scenario 4: capture_daemon_overrides read into ROSTER_DAEMON_OVERRIDE ---"
d4_dir="$(mktemp -d)"
trap 'rm -r -- "$d4_dir" 2>/dev/null || true' EXIT
d4_params="$d4_dir/watch_params.json"
python3 -c '
import json, sys
data = {
    "roster": [
        "agent_plain_no_override",
        "agent_plain_with_override",
        {"agent_id": "agent_dict_with_override", "hostname": "boxc", "tmux_session": "sess"},
    ],
    "capture_daemon_overrides": {
        "agent_plain_with_override": "d_PLAINOVERRIDE00000000000",
        "agent_dict_with_override": "d_DICTOVERRIDE0000000000000",
    },
}
json.dump(data, open(sys.argv[1], "w"))
' "$d4_params"

load_roster "$d4_params"

assert_eq "capture_daemon_overrides: roster has 3 entries" "3" "${#ROSTER[@]}"
assert_eq "capture_daemon_overrides: entry 0 agent id" "agent_plain_no_override" "${ROSTER[0]}"
assert_eq "capture_daemon_overrides: plain string entry with NO override reads empty" "" "${ROSTER_DAEMON_OVERRIDE[0]}"
assert_eq "capture_daemon_overrides: entry 1 agent id" "agent_plain_with_override" "${ROSTER[1]}"
assert_eq "capture_daemon_overrides: plain string entry WITH override reads its daemon id" "d_PLAINOVERRIDE00000000000" "${ROSTER_DAEMON_OVERRIDE[1]}"
assert_eq "capture_daemon_overrides: entry 2 agent id" "agent_dict_with_override" "${ROSTER[2]}"
assert_eq "capture_daemon_overrides: dict-form entry's hostname still reads correctly (field alignment intact)" "boxc" "${ROSTER_HOSTNAME[2]}"
assert_eq "capture_daemon_overrides: dict-form entry's tmux_session still reads correctly" "sess" "${ROSTER_TMUX_SESSION[2]}"
assert_eq "capture_daemon_overrides: dict-form entry WITH override reads its daemon id" "d_DICTOVERRIDE0000000000000" "${ROSTER_DAEMON_OVERRIDE[2]}"

rm -r -- "$d4_dir"
trap - EXIT

# Default/absent capture_daemon_overrides -> every entry inert (empty).
d4b_dir="$(mktemp -d)"
trap 'rm -r -- "$d4b_dir" 2>/dev/null || true' EXIT
d4b_params="$d4b_dir/watch_params.json"
python3 -c '
import json, sys
json.dump({"roster": ["agent_a", "agent_b"]}, open(sys.argv[1], "w"))
' "$d4b_params"
load_roster "$d4b_params"
assert_eq "capture_daemon_overrides absent from watch_params.json: entry 0 inert" "" "${ROSTER_DAEMON_OVERRIDE[0]}"
assert_eq "capture_daemon_overrides absent from watch_params.json: entry 1 inert" "" "${ROSTER_DAEMON_OVERRIDE[1]}"
rm -r -- "$d4b_dir"
trap - EXIT

# is_declared_inactive resolves the roster entry and each declared entry through `thrum team` (roster_member), so this
# test serves canned team rows and a canned whoami from a thrum shim (no daemon is touched): D_TEAM holds the rows
# for every scoped read, D_OWN is this daemon's ID ("" = an old-form daemon with no daemon_id). set_own re-arms the
# once-per-run daemon-ID cache.
D_TEAM='{"team":{"members":[]}}'
D_OWN=""
thrum() {
  case "$1" in
    team) printf '%s\n' "$D_TEAM" ;;
    whoami) [ -z "$D_OWN" ] || printf '{"agent_id":"x@%s","name":"x","daemon_id":"%s"}\n' "$D_OWN" "$D_OWN" ;;
    *) return 0 ;;
  esac
}
# shellcheck disable=SC2034 # the cache variables belong to the sourced roster-watch.sh
set_own() { D_OWN="$1"; OWN_DAEMON_ID_READ=0; OWN_DAEMON_ID=""; }

# Declared-inactive members: expected_inactive_roster / sleeping_roster are
# read by load_roster; a member in neither list is not declared.
d5_dir="$(mktemp -d)"
trap 'rm -r -- "$d5_dir" 2>/dev/null || true' EXIT
d5_params="$d5_dir/watch_params.json"
python3 -c '
import json, sys
json.dump({"roster": ["agent_a", "agent_b", "agent_c"], "expected_inactive_roster": ["agent_a"], "sleeping_roster": [{"agent_id": "agent_b"}]}, open(sys.argv[1], "w"))
' "$d5_params"
load_roster "$d5_params"
is_declared_inactive agent_a && d5_a=yes || d5_a=no
is_declared_inactive agent_b && d5_b=yes || d5_b=no
is_declared_inactive agent_c && d5_c=yes || d5_c=no
assert_eq "declared roster: expected_inactive_roster member is declared" "yes" "$d5_a"
assert_eq "declared roster: sleeping_roster object member is declared" "yes" "$d5_b"
assert_eq "declared roster: undeclared member is not declared (control)" "no" "$d5_c"
python3 -c '
import json, sys
json.dump({"roster": ["agent_a"]}, open(sys.argv[1], "w"))
' "$d5_params"
load_roster "$d5_params"
is_declared_inactive agent_a && d5_none=yes || d5_none=no
assert_eq "declared roster: absent lists declare nothing" "no" "$d5_none"
python3 -c '
import json, sys
json.dump({"roster": ["agent_a", "null", "agent_b", "agent_c"], "expected_inactive_roster": [None, 7, {"agent": "agent_a"}, {"name": "agent_a"}, "agent_c"], "sleeping_roster": {"x": "agent_b"}}, open(sys.argv[1], "w"))
' "$d5_params"
load_roster "$d5_params"
is_declared_inactive agent_a && d5_a2=yes || d5_a2=no
is_declared_inactive null && d5_null=yes || d5_null=no
is_declared_inactive agent_b && d5_b2=yes || d5_b2=no
is_declared_inactive agent_c && d5_c2=yes || d5_c2=no
assert_eq "declared roster: only names and {agent_id} count; {agent}/{name} declare nothing" "no" "$d5_a2"
assert_eq "declared roster: a null entry excuses nothing" "no" "$d5_null"
assert_eq "declared roster: a dict-valued list excuses nothing" "no" "$d5_b2"
assert_eq "declared roster: a bad entry does not drop the good ones after it" "yes" "$d5_c2"
# A qualified entry is kept as given and declares exactly that ID (never the bare name, never another daemon's).
python3 -c '
import json, sys
json.dump({"roster": ["agent_a@d_TESTDAEMON", "agent_b@d_TESTDAEMON", "agent_c"], "expected_inactive_roster": [{"agent_id": "agent_a@d_TESTDAEMON"}], "sleeping_roster": [{"agent_id": "agent_b@d_TESTDAEMON"}, "agent_c@d_TESTDAEMON"]}, open(sys.argv[1], "w"))
' "$d5_params"
load_roster "$d5_params"
is_declared_inactive agent_a@d_TESTDAEMON && d5_qa=yes || d5_qa=no
is_declared_inactive agent_b@d_TESTDAEMON && d5_qb=yes || d5_qb=no
is_declared_inactive agent_c@d_TESTDAEMON && d5_qc=yes || d5_qc=no
is_declared_inactive agent_a && d5_qbare=yes || d5_qbare=no
is_declared_inactive agent_a@d_OTHER && d5_qother=yes || d5_qother=no
is_declared_inactive agent_c && d5_qcbare=yes || d5_qcbare=no
assert_eq "declared roster: {agent_id=name@daemon} in expected_inactive_roster declares that ID" "yes" "$d5_qa"
assert_eq "declared roster: {agent_id=name@daemon} in sleeping_roster declares that ID" "yes" "$d5_qb"
assert_eq "declared roster: string name@daemon declares that ID" "yes" "$d5_qc"
assert_eq "declared roster: a qualified declaration does not declare the bare name (control)" "no" "$d5_qbare"
assert_eq "declared roster: a qualified declaration does not declare another daemon's ID (control)" "no" "$d5_qother"
assert_eq "declared roster: string name@daemon does not declare the bare name (control)" "no" "$d5_qcbare"
assert_eq "load_roster keeps a qualified roster entry as given" "agent_a@d_TESTDAEMON" "${ROSTER[0]}"
assert_eq "load_roster keeps a bare roster entry as given (control)" "agent_c" "${ROSTER[2]}"
# Resolved comparison: the roster entry and each declared entry are resolved to an agent by the three rules, then the
# agent IDs are compared (the string tests above run with no team rows, where only identical strings match).
decl() { # decl <declared entry...> : load a params file whose expected_inactive_roster is the given entries
  python3 -c '
import json, sys
json.dump({"roster": ["alice"], "expected_inactive_roster": sys.argv[2:]}, open(sys.argv[1], "w"))
' "$d5_params" "$@"
  load_roster "$d5_params"
}
cand() { is_declared_inactive "$1" 2>"$d5_dir/err" && echo yes || echo no; }
# declared alice@dL, roster bare alice, dL is this daemon (alice is the local row): excused
set_own dL
D_TEAM='{"team":{"members":[{"agent_id":"alice","name":"alice","is_local":true},{"agent_id":"alice@d1","name":"alice","is_local":false}]}}'
decl alice@dL
assert_eq "declared roster: a bare roster alice is excused by a declared alice@<this daemon>" "yes" "$(cand alice)"
# declared alice@d1, but the roster's alice is this daemon's own agent: not excused (another daemon's agent)
decl alice@d1
assert_eq "declared roster: a bare roster alice that resolves to this daemon's alice is NOT excused by alice@d1" "no" "$(cand alice)"
# only one alice anywhere, on another daemon: the bare roster entry is that agent, so the declaration excuses it
D_TEAM='{"team":{"members":[{"agent_id":"alice@d1","name":"alice","is_local":false}]}}'
set_own dX
decl alice@d1
assert_eq "declared roster: a bare roster alice is excused by alice@d1 when alice is unique" "yes" "$(cand alice)"
# an ambiguous declared entry excuses nothing and is reported
D_TEAM='{"team":{"members":[{"agent_id":"alice@d1","name":"alice","is_local":false},{"agent_id":"alice@d2","name":"alice","is_local":false}]}}'
decl alice
assert_eq "declared roster: an ambiguous declared entry excuses nothing" "no" "$(cand alice@d1)"
assert_eq "declared roster: the ambiguous declared entry is reported naming every candidate" "1" "$(grep -cF "ambiguous roster entry 'alice': candidates alice@d1 alice@d2" "$d5_dir/err")"
decl alice@d2
assert_eq "declared roster: control: the full ID of one of the two excuses that one" "yes" "$(cand alice@d2)"
assert_eq "declared roster: control: it does not excuse the other one" "no" "$(cand alice@d1)"
# is_local is the row's locality: a bare alice with is_local false is another daemon's agent, never qualified with this
# daemon, so a declared alice@<this daemon> does not excuse it (control: is_local true does).
set_own dL
D_TEAM='{"team":{"members":[{"agent_id":"alice","name":"alice","is_local":false}]}}'
decl alice@dL
assert_eq "declared roster: a bare alice with is_local false is NOT excused by alice@<this daemon>" "no" "$(cand alice)"
D_TEAM='{"team":{"members":[{"agent_id":"alice","name":"alice","is_local":true}]}}'
assert_eq "declared roster: control: the same bare row with is_local true is excused" "yes" "$(cand alice)"
D_TEAM='{"team":{"members":[{"agent_id":"alice","name":"alice"}]}}'
assert_eq "declared roster: a bare row with no is_local key is local and excused" "yes" "$(cand alice)"
# the daemon ID is read once however many entries are resolved
set_own dL
D_TEAM='{"team":{"members":[{"agent_id":"alice","name":"alice","is_local":true}]}}'
: >"$d5_dir/wcalls"
thrum() {
  case "$1" in
    team) printf '%s\n' "$D_TEAM" ;;
    whoami) echo whoami >>"$d5_dir/wcalls"; printf '{"daemon_id":"%s"}\n' "$D_OWN" ;;
    *) return 0 ;;
  esac
}
decl alice@dL alice@dL
is_declared_inactive alice >/dev/null 2>&1; is_declared_inactive alice >/dev/null 2>&1
assert_eq "declared roster: whoami is read once for the whole run" "1" "$(wc -l <"$d5_dir/wcalls" | tr -d ' ')"
thrum() {
  case "$1" in
    team) printf '%s\n' "$D_TEAM" ;;
    whoami) [ -z "$D_OWN" ] || printf '{"agent_id":"x@%s","name":"x","daemon_id":"%s"}\n' "$D_OWN" "$D_OWN" ;;
    *) return 0 ;;
  esac
}
set_own ""
D_TEAM='{"team":{"members":[]}}'
rm -r -- "$d5_dir"
trap - EXIT

# run_capture_cycle with a roster member whose capture fails (agent not found):
# an undeclared member lands in FAILED; a declared-inactive member lands nowhere.
# Shims replace every call that would touch tmux, ssh, the daemon or the archive.
(
  d6_dir="$(mktemp -d)"
  trap 'rm -r -- "$d6_dir" 2>/dev/null || true' EXIT
  thrum() {
    case "$1" in
      tmux) echo "capture $3" >>"$d6_dir/captures"; echo "Error: tmux.capture: RPC error -32000: rpcrouter: local agent not found"; return 1 ;;
      *) return 0 ;;
    esac
  }
  ssh_capture_pane() { return 1; }
  resolve_session() { echo "sess"; }
  agent_is_local() { return 1; }
  measure_geometry_json() { :; }
  check_ghost_tip() { :; }
  archive_source_file() { :; }
  archive_agent_file() { :; }
  outdir="$d6_dir"
  ROSTER=(ghost); ROSTER_HOSTNAME=(""); ROSTER_TMUX_SESSION=(""); ROSTER_RUNTIME=(""); ROSTER_DAEMON_OVERRIDE=("")
  USE_JEV=0
  echo "fixture=${#ROSTER[@]}/${#ROSTER_HOSTNAME[@]}/${#ROSTER_TMUX_SESSION[@]}/${#ROSTER_RUNTIME[@]}/${#ROSTER_DAEMON_OVERRIDE[@]} jev=${USE_JEV}"

  FAILED=(); DEGRADED=(); CAPTURED=(); DECLARED_INACTIVE=()
  run_capture_cycle "${outdir}/undeclared.txt" cap1 ts1 >/dev/null 2>&1
  echo "undeclared=${FAILED[*]-} declared=${DECLARED_INACTIVE[*]-} captured=${#CAPTURED[@]}"

  FAILED=(); DEGRADED=(); CAPTURED=(); DECLARED_INACTIVE=(ghost)
  run_capture_cycle "${outdir}/declared.txt" cap2 ts2 >/dev/null 2>&1
  echo "declared_failed=${FAILED[*]-}"
  echo "declared_degraded=${DEGRADED[*]-}"
  echo "declared_list=${DECLARED_INACTIVE[*]-} captured=${#CAPTURED[@]}"
  echo "declared_marker=$(grep -c 'DECLARED INACTIVE' "${outdir}/declared.txt")"

  # An ambiguous roster entry (found by roster_self_check) is skipped, not captured; the rest of the roster still is.
  : >"$d6_dir/captures"
  ROSTER=(alice ghost); ROSTER_HOSTNAME=("" ""); ROSTER_TMUX_SESSION=("" ""); ROSTER_RUNTIME=("" ""); ROSTER_DAEMON_OVERRIDE=("" "")
  FAILED=(); DEGRADED=(); CAPTURED=(); DECLARED_INACTIVE=(); ROSTER_AMBIGUOUS=(alice)
  run_capture_cycle "${outdir}/ambiguous.txt" cap3 ts3 >/dev/null 2>&1
  echo "amb_captures=$(tr '\n' ',' <"$d6_dir/captures")"
  echo "amb_failed=${FAILED[*]-}"
  echo "amb_skipped=$(grep -c 'SKIPPED: ambiguous roster entry' "${outdir}/ambiguous.txt")"
  # Control: the same roster with nothing marked ambiguous captures alice too.
  : >"$d6_dir/captures"
  FAILED=(); DEGRADED=(); CAPTURED=()
  # shellcheck disable=SC2034 # read by is_ambiguous_entry in the sourced roster-watch.sh
  ROSTER_AMBIGUOUS=()
  run_capture_cycle "${outdir}/notambiguous.txt" cap4 ts4 >/dev/null 2>&1
  echo "ctl_captures=$(tr '\n' ',' <"$d6_dir/captures")"
) > "${TMPDIR:-/tmp}/rw-cycle.$$" 2>&1
d6_out="$(cat "${TMPDIR:-/tmp}/rw-cycle.$$")"; rm -f -- "${TMPDIR:-/tmp}/rw-cycle.$$"
assert_eq "run_capture_cycle: fixture arrays are aligned (one member, no JEV)" "fixture=1/1/1/1/1 jev=0" "$(printf '%s\n' "$d6_out" | grep '^fixture=')"
assert_eq "run_capture_cycle: undeclared failing member is FAILED and captured nothing" "undeclared=ghost declared= captured=0" "$(printf '%s\n' "$d6_out" | grep '^undeclared=')"
assert_eq "run_capture_cycle: declared-inactive failing member is not FAILED" "declared_failed=" "$(printf '%s\n' "$d6_out" | grep '^declared_failed=')"
assert_eq "run_capture_cycle: declared-inactive failing member is not DEGRADED" "declared_degraded=" "$(printf '%s\n' "$d6_out" | grep '^declared_degraded=')"
assert_eq "run_capture_cycle: declared-inactive member captured nothing" "declared_list=ghost captured=0" "$(printf '%s\n' "$d6_out" | grep '^declared_list=')"
assert_eq "run_capture_cycle: declared-inactive member is noted in the capture file" "declared_marker=1" "$(printf '%s\n' "$d6_out" | grep '^declared_marker=')"
assert_eq "run_capture_cycle: an ambiguous entry is not captured (only ghost is)" "amb_captures=capture ghost," "$(printf '%s\n' "$d6_out" | grep '^amb_captures=')"
assert_eq "run_capture_cycle: the skipped ambiguous entry is not a FAILED capture" "amb_failed=ghost" "$(printf '%s\n' "$d6_out" | grep '^amb_failed=')"
assert_eq "run_capture_cycle: the skipped entry is noted in the capture file" "amb_skipped=1" "$(printf '%s\n' "$d6_out" | grep '^amb_skipped=')"
assert_eq "run_capture_cycle: control: with nothing ambiguous alice is captured too" "ctl_captures=capture alice,capture ghost," "$(printf '%s\n' "$d6_out" | grep '^ctl_captures=')"

# ---------------------------------------------------------------------------
echo "----------------------------------------"
echo "roster-watch: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
