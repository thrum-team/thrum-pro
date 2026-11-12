#!/usr/bin/env bash
# Scope check: reports branches gone from origin, large branches and stalled branches to the merge king.
# Run it from the checkout; it sources lib.sh from its own directory. Needs: jq, git, thrum. Bash 3.2 safe. Calls no
# bare timeout. It never deletes a branch or a remote ref: its fetch is a plain `git fetch` and it only lists and warns.
#
# Env (test seam): CHECKS_NOW is the current time in epoch seconds (default: date +%s).
# Exit: 0 after a run (a report was sent, or nothing changed); 1 when the run could not be done, with the reason on stderr.
# shellcheck disable=SC1091  # lib.sh is found at run time, next to this file
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
. "$HERE/lib.sh"

CHECK_NAME=scope
export CHECK_NAME

root="$(_chk_root)" || exit 1
[ -n "$root" ] || { echo "not inside a git checkout" >&2; exit 1; }
load_config || exit 1

now="${CHECKS_NOW:-$(date +%s)}"
tdir="$(_chk_thrum_dir)" || exit 1
mkdir -p "$tdir/results/checks-state" || { echo "cannot create $tdir/results/checks-state" >&2; exit 1; }
stamp="$tdir/results/checks-state/scope.delivered"

trunk="$(thrum config show "$CHK_MERGE_TARGET_FROM" --json 2>/dev/null | jq -r '.value // empty' 2>/dev/null)"
if [ -z "$trunk" ]; then
  missing_notice orchestration.merge_target onboarding-gates
  exit 1
fi
if git -C "$root" rev-parse -q --verify "refs/heads/$trunk" >/dev/null; then
  trunk_ref="refs/heads/$trunk"
elif git -C "$root" rev-parse -q --verify "refs/remotes/origin/$trunk" >/dev/null; then
  trunk_ref="refs/remotes/origin/$trunk"
else
  echo "the merge target $trunk is not a branch in this checkout (neither refs/heads/$trunk nor refs/remotes/origin/$trunk)" >&2
  exit 1
fi

# The report window: the time since the previous delivered report, at most cadence_hours.
window_start=$((now - CHK_CADENCE_HOURS * 3600))
if [ -f "$stamp" ]; then
  last="$(cat "$stamp")"
  case "$last" in
    '' | *[!0-9]*) ;;
    *) [ "$last" -gt "$window_start" ] && window_start="$last" ;;
  esac
fi

fetch_line=""
fetch_line="$(fetch_or_report origin 2>&1)" || true

# Candidate issue ids from a branch name: pairs, triples, then single tokens of its hyphen-joined words.
candidates() {
  printf '%s\n' "${1#*/}" | tr '/_.' '\n\n\n' | awk -F- '
    { for (i = 1; i < NF; i++) print $i "-" $(i + 1)
      for (i = 1; i < NF - 1; i++) print $i "-" $(i + 1) "-" $(i + 2)
      for (i = 1; i <= NF; i++) print $i }' | sed -e '/^$/d' -e '/^-/d' | head -n 24
}

tracker="$(thrum config show tracker --json 2>/dev/null | jq -r '.value // empty' 2>/dev/null)"

# ask_text BRANCH REF: the issue title for the id in the branch name, else the first commit subject on REF.
ask_text() {
  local b="$1" ref="$2" id out text=""
  case "$tracker" in
    beads | native)
      while read -r id; do
        if [ "$tracker" = "beads" ]; then
          out="$(bd show "$id" --json 2>/dev/null)" || continue
        else
          out="$(thrum issue show "$id" --json 2>/dev/null)" || continue
        fi
        text="$(printf '%s' "$out" | jq -r '[.. | objects | .title? // empty] | first // empty' 2>/dev/null)"
        [ -n "$text" ] && break
      done <<EOF2
$(candidates "$b")
EOF2
      ;;
  esac
  if [ -z "$text" ]; then
    text="$(git -C "$root" log --reverse --format=%s "$trunk_ref..$ref" 2>/dev/null | head -n 1)"
  fi
  printf '%s' "$text" | tr '\n"' " '" | cut -c 1-160
}

roster="$(thrum team --all --json 2>/dev/null)"
# This daemon's own ID (`daemon_id` from whoami), read once for this run; absent on an old-form daemon, where no row
# is qualified and every row is local.
# Read here through the lib's cache, in this shell, so deliver (which runs in a pipeline subshell) does not read it again.
_chk_own_daemon_id
own="$CHK_OWN_DAEMON_ID"
# A team row with is_local false whose id names this daemon: the flag wins (the row is not local); one stderr line
# per such row, once per run.
[ -z "$own" ] || printf '%s' "$roster" | jq -r --arg own "$own" '.team.members[]? | select(.is_local == false) | (.agent_id // "") | select(endswith("@" + $own))' 2>/dev/null |
  while IFS= read -r w; do printf "team row '%s' has is_local false but names this daemon\n" "$w" >&2; done
# Names are compared bare (git author names carry no daemon part). A name is listed once whatever the number of
# daemons that have it; no row is picked for an ambiguous name. Paused: a bare name means this daemon's agent
# first (a row that carries a boolean is_local is local exactly when it says so; without one, an agent_id with no
# "@" or a daemon half that is this daemon; a bare row `a` and a row `a@<this daemon>` are one agent), else the single remote one; a name that is ambiguous (several distinct IDs in
# the group that would be picked from) is never counted as paused. A name is .name when non-empty, else the id up to "@".
roster_ids="$(printf '%s' "$roster" | jq -r '[.team.members[]? | ((.name // "" | select(. != "")) // ((.agent_id // "") | split("@")[0])) | select(. != null and . != "")] | unique | .[]' 2>/dev/null)"
paused="$(printf '%s' "$roster" | jq -r --arg own "$own" '
  [.team.members[]? | (.agent_id // "") as $id
    | {id: $id,
       nm: ((.name // "" | select(. != "")) // ($id | split("@")[0])),
       lcl: (if (.is_local | type) == "boolean" then .is_local else ((($id | contains("@")) | not) or ($own != "" and ($id | endswith("@" + $own)))) end),
       p: (.phase == "sleeping" or .phase == "parked" or .presentation_state == "sleeping" or .presentation_state == "parked")}
    | .id = (if ($id | contains("@")) or $own == "" or (.lcl | not) then $id else $id + "@" + $own end)]
  | group_by(.nm)[]
  | . as $g
  | ([$g[] | select(.lcl)] | unique_by(.id)) as $l
  | ([$g[] | select(.lcl | not)] | unique_by(.id)) as $x
  | (if ($l | length) == 1 then $l[0] elif ($l | length) == 0 and ($x | length) == 1 then $x[0] else null end)
  | select(. != null and .p) | .nm' 2>/dev/null)"
is_paused() { printf '%s\n' "$paused" | grep -qxF -- "$1"; }

nl='
'
gone_rows=""; gone_sig=""; large_rows=""; large_sig=""; stalled_rows=""; stalled_sig=""; paused_rows=""

# Gone from origin: a remote-tracking ref that origin no longer lists. Nothing is removed.
origin_gone_load
if [ "$CHK_GONE_OK" = 1 ]; then
  while read -r name; do
    is_watched "$name" || continue
    if git -C "$root" rev-parse -q --verify "refs/heads/$name" >/dev/null; then kept="local ref kept"; else kept="remote-tracking ref kept"; fi
    if is_protected "$name"; then
      row="- $name: push it back (a protected branch is gone from origin; $kept)"
    else
      row="- $name: gone from origin ($kept; not deleted)"
    fi
    gone_rows="$gone_rows$row$nl"
    gone_sig="$gone_sig$row$nl"
  done <<EOF2
$CHK_GONE
EOF2
else
  row="- could not list origin's branches; the gone-from-origin list is not checked this run"
  gone_rows="$gone_rows$row$nl"
  gone_sig="$gone_sig$row$nl"
fi

# prod_stat REF: "ADDED_LINES PRODUCTION_FILES" of trunk...REF, test globs and *.md left out; a binary file adds no lines.
prod_stat() {
  local a f l=0 n=0
  while IFS="$(printf '\t')" read -r a _ f; do
    case "$f" in *.md) continue ;; esac
    is_test_file "$f" && continue
    n=$((n + 1)); [ "$a" = - ] || l=$((l + a))
  done <<EOF2
$(git -C "$root" -c core.quotepath=false diff --no-renames --numstat "$trunk_ref...$1")
EOF2
  echo "$l $n"
}

# Large and stalled branches.
while IFS="$(printf '\t')" read -r b ref where; do
  [ -n "$b" ] || continue
  ahead="$(git -C "$root" rev-list --count "$trunk_ref..$ref" 2>/dev/null || echo 0)"
  [ "$ahead" -gt 0 ] || continue
  disp="$b"; [ "$where" = origin ] && disp="$b (on origin only)"
  tip_ct="$(git -C "$root" log -1 --format=%ct "$ref")"
  stat="$(prod_stat "$ref")"
  lines="${stat% *}"; files="${stat#* }"
  if [ "$lines" -gt "$CHK_SIZE_LINES" ] || [ "$files" -gt "$CHK_SIZE_FILES" ]; then
    large_sig="$large_sig- $disp: large ($lines lines, $files files)$nl"
    if [ "$tip_ct" -ge "$window_start" ]; then
      large_rows="$large_rows- $disp: large ($lines lines, $files files); ask: \"$(ask_text "$b" "$ref")\"$nl"
    fi
  fi
  age_h=$(((now - tip_ct) / 3600))
  if [ "$age_h" -ge "$CHK_STALLED_HOURS" ]; then
    owner=""
    for cand in "$(git -C "$root" log -1 --format=%an "$ref")" "$(git -C "$root" log -1 --format=%cn "$ref")"; do
      if [ -n "$cand" ] && printf '%s\n' "$roster_ids" | grep -qxF -- "$cand"; then owner="$cand"; break; fi
    done
    if [ -n "$owner" ] && is_paused "$owner"; then
      paused_rows="$paused_rows- $disp: STALLED (owner paused); no commit for $age_h hours; owner $owner is sleeping or parked, so it is not chased$nl"
    else
      row="- $disp: STALLED; no commit for $age_h hours; owner ${owner:-unknown}"
      stalled_rows="$stalled_rows$row$nl"
      stalled_sig="$stalled_sig$row$nl"
    fi
  fi
done <<EOF2
$(branch_list)
EOF2

fetch_rows=""
[ -n "$fetch_line" ] && fetch_rows="- $fetch_line$nl"

coupling="coupling not measured"
ob="$root/$CHK_POLICY_REL/onboarding.json"
if [ -f "$ob" ]; then
  cdate="$(jq -r 'if (.sections.S3.status // "") == "skipped" then "" else (.sections.S3.date // "") end' "$ob" 2>/dev/null)"
  [ -n "$cdate" ] && coupling="coupling last measured $cdate"
fi

sig_text="$fetch_rows$gone_sig$large_sig$stalled_sig"
rows="$fetch_rows$gone_rows$large_rows$stalled_rows"
if [ -z "$rows" ]; then
  # Nothing new to say; still move the signature so a later change is seen.
  printf '%s' "$sig_text" | changed_or_quiet scope >/dev/null || true
  echo "scope-check: nothing to report"
  exit 0
fi
if ! printf '%s' "$sig_text" | changed_or_quiet scope; then
  echo "scope-check: no change since the last run"
  exit 0
fi

# portable-ok: date -d is the GNU form; the BSD form -r follows it and the epoch is the last fallback
window_date="$(date -u -d "@$window_start" '+%Y-%m-%d %H:%M' 2>/dev/null || date -u -r "$window_start" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$window_start")"
n_rows="$(printf '%s' "$rows" | grep -c '^- ')"
report="Scope check: $n_rows item(s) need a look
window: since $window_date UTC (at most $CHK_CADENCE_HOURS hours); $coupling
"
[ -n "$fetch_rows" ] && report="$report${nl}Fetch:$nl$fetch_rows"
[ -n "$gone_rows" ] && report="$report${nl}Gone from origin (nothing was deleted; list and warn only):$nl$gone_rows"
[ -n "$large_rows" ] && report="$report${nl}Large branches:$nl$large_rows"
if [ -n "$stalled_rows$paused_rows" ]; then report="$report${nl}Stalled branches:$nl$stalled_rows$paused_rows"; fi

if printf '%s\n' "$report" | deliver; then
  printf '%s\n' "$report" | write_report scope || true
  printf '%s\n' "$now" > "$stamp"
  echo "scope-check: report delivered"
  exit 0
fi
# Delivery failed (the lib has said why): forget the signature so the next run tries again.
rm -f "$tdir/results/checks-state/scope.sig"
exit 1
