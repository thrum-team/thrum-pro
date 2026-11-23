#!/usr/bin/env bash
# shellcheck disable=SC2034  # the CHK_* variables are this library's output, read by the check scripts that source it
# Shared library for the onboarding check scripts. Source it; do not run it.
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# Needs: jq, git, thrum. Bash 3.2 safe. Calls no bare timeout.
#
# Env (test seams; the defaults are the real locations):
#   CHECKS_ROOT   the checkout root (default: git rev-parse --show-toplevel)
#
# Functions: load_config, is_watched, is_test_file, origin_gone_load, branch_list, changed_or_quiet, deliver, write_report, fetch_or_report, missing_notice. _chk_need_thrum is
# internal: load_config calls it first and deliver before its first thrum call.
# A function that cannot do its job prints one line to stderr and returns 1; the calling check script stops.

CHK_POLICY_REL=".thrum/policy"

_chk_root() {
  if [ -n "${CHECKS_ROOT:-}" ]; then
    printf '%s\n' "$CHECKS_ROOT"
  else
    git rev-parse --show-toplevel 2>/dev/null
  fi
}

_chk_need_jq() {
  command -v jq >/dev/null 2>&1 || { echo "jq is required by the check scripts and was not found" >&2; return 1; }
}

# Monitors run a check script with a fixed PATH, so thrum can be missing there although the owner's shell finds it. Every
# check script runs load_config before any thrum call of its own, so this one test covers them. It is not a missing-policy
# notice: it never calls missing_notice, never writes "reported" and sends no message, so a thrum that cannot run is never
# reported as a missing file or key.
_chk_need_thrum() {
  command -v thrum >/dev/null 2>&1 || {
    echo "CHECK ERROR: thrum is not on this check's PATH ($PATH); link or install thrum into a directory on that PATH" >&2
    return 1
  }
}

# The folder that holds .thrum/results: the checkout's own .thrum, or the folder .thrum/redirect names in a worktree.
_chk_thrum_dir() {
  local root dir target
  root="$(_chk_root)" || return 1
  [ -n "$root" ] || { echo "not inside a git checkout, so .thrum cannot be located" >&2; return 1; }
  dir="$root/.thrum"
  if [ -f "$dir/redirect" ]; then
    target="$(head -n 1 "$dir/redirect")"
    if [ -z "$target" ] || [ ! -d "$target" ]; then
      echo "$dir/redirect names a folder that does not exist: $target" >&2
      return 1
    fi
    dir="$target"
  fi
  printf '%s\n' "$dir"
}

# load_config: reads .thrum/policy/checks.json and sets CHK_* variables. The file and every key are required, with two
# exceptions: deliver_to (empty when absent; deliver then resolves the merge king) and dashboard_generator (optional).
# The defaults in checks-schema.md are what onboarding-checks offers and writes, never values this function falls back to.
# A missing file or key calls missing_notice (once per signature) and returns 1, so the check stops without a report.
# An unreadable file or an invalid value prints one line and returns 1.
load_config() {
  local root file out keys k skill
  _chk_need_thrum || return 1
  _chk_need_jq || return 1
  root="$(_chk_root)" || return 1
  file="$root/$CHK_POLICY_REL/checks.json"
  if [ ! -f "$file" ]; then
    missing_notice "$CHK_POLICY_REL/checks.json" onboarding-checks
    return 1
  fi
  if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    echo "$CHK_POLICY_REL/checks.json is not a JSON object; run onboarding-checks to rewrite it" >&2
    return 1
  fi
  CHK_FILE="$file"
  # The coordinator is read first, best effort, so a notice for any other key can reach it.
  CHK_COORDINATOR="$(jq -r '.coordinator // ""' "$file")"
  keys="cadence_hours branch_globs size_threshold.lines size_threshold.files stalled_hours test_globs delivery coordinator merge_target_from security_doc"
  for k in $keys; do
    if [ "$(jq -r --arg k "$k" 'getpath($k | split(".")) | if . == null then "absent" else "present" end' "$file")" = "absent" ]; then
      skill=onboarding-checks
      [ "$k" = "coordinator" ] && skill=onboarding-coordinator
      missing_notice "$CHK_POLICY_REL/checks.json" "$skill" "$k"
      return 1
    fi
  done
  CHK_CADENCE_HOURS="$(jq -r '.cadence_hours' "$file")"
  CHK_BRANCH_GLOBS="$(jq -r '.branch_globs | join(" ")' "$file")"
  CHK_SIZE_LINES="$(jq -r '.size_threshold.lines' "$file")"
  CHK_SIZE_FILES="$(jq -r '.size_threshold.files' "$file")"
  CHK_STALLED_HOURS="$(jq -r '.stalled_hours' "$file")"
  CHK_TEST_GLOBS="$(jq -r '.test_globs | join(" ")' "$file")"
  CHK_DELIVERY="$(jq -r '.delivery' "$file")"
  CHK_DELIVER_TO="$(jq -r '.deliver_to // ""' "$file")"
  CHK_MERGE_TARGET_FROM="$(jq -r '.merge_target_from' "$file")"
  CHK_SECURITY_DOC="$(jq -r '.security_doc' "$file")"
  CHK_DASHBOARD_GENERATOR="$(jq -r '.dashboard_generator // ""' "$file")"
  case "$CHK_DELIVERY" in
    auto | pane | inbox) ;;
    *) echo "$CHK_POLICY_REL/checks.json key delivery must be auto, pane or inbox, found: $CHK_DELIVERY" >&2; return 1 ;;
  esac
  for out in "$CHK_CADENCE_HOURS" "$CHK_SIZE_LINES" "$CHK_SIZE_FILES" "$CHK_STALLED_HOURS"; do
    case "$out" in
      '' | *[!0-9]*) echo "$CHK_POLICY_REL/checks.json has a number key that is not a whole number: $out" >&2; return 1 ;;
    esac
  done
  return 0
}

# is_protected NAME: the merge target $trunk (set by the caller), main, release/*. is_watched: protected or a branch_globs prefix.
is_protected() {
  case "$1" in
    "${trunk:-}" | main | release/*) return 0 ;;
  esac
  return 1
}
is_watched() {
  local g
  is_protected "$1" && return 0
  for g in $CHK_BRANCH_GLOBS; do
    case "$1" in "$g"*) return 0 ;; esac
  done
  return 1
}

# is_test_file PATH: 0 when PATH matches a test_globs entry (an entry ending in / names a folder anywhere in the path).
is_test_file() {
  local g
  # shellcheck disable=SC2254  # the test glob is meant as a glob
  while IFS= read -r g; do
    case "$g" in
      */) case "/$1" in *"/$g"*) return 0 ;; esac ;;
      *) case "$1" in $g | */$g) return 0 ;; esac ;;
    esac
  done <<EOF2
$(printf '%s\n' "$CHK_TEST_GLOBS" | tr ' ' '\n')
EOF2
  return 1
}

# origin_gone_load: one git ls-remote. Sets CHK_GONE (remote-tracking branch names origin no longer lists, one per line)
# and CHK_GONE_OK (1; 0 when origin cannot be listed, then CHK_GONE is empty and remote-tracking refs are read as they are).
origin_gone_load() {
  local heads n
  CHK_GONE=""; CHK_GONE_OK=0
  heads="$(git -C "$root" ls-remote --heads origin 2>/dev/null)" || return 0
  CHK_GONE_OK=1
  heads="$(printf '%s\n' "$heads" | awk '{print $2}')"
  for n in $(git -C "$root" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin); do
    [ "$n" = HEAD ] || printf '%s\n' "$heads" | grep -qxF "refs/heads/$n" || CHK_GONE="$CHK_GONE$n
"
  done
}

# branch_list: after origin_gone_load, prints NAME TAB FULLREF TAB local|origin (origin: no local ref) for each watched branch, once, from the union
# of refs/heads and refs/remotes/origin. Never HEAD, main, release/* or the merge target. A remote-tracking ref origin no
# longer lists counts only when no local ref of that name exists. With both: the descendant, else the later %ct, else local.
branch_list() {
  local n lr or w
  { git -C "$root" for-each-ref --format='%(refname:strip=2)' refs/heads
    git -C "$root" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin; } | sort -u | while IFS= read -r n; do
    case "$n" in HEAD | '') continue ;; esac
    is_protected "$n" && continue
    is_watched "$n" || continue
    lr="refs/heads/$n"; or="refs/remotes/origin/$n"
    git -C "$root" rev-parse -q --verify "$lr" >/dev/null || lr=""
    w=local; [ -n "$lr" ] || w=origin
    git -C "$root" rev-parse -q --verify "$or" >/dev/null && ! printf '%s' "$CHK_GONE" | grep -qxF -- "$n" || or=""
    if [ -n "$lr" ] && [ -n "$or" ]; then
      if git -C "$root" merge-base --is-ancestor "$or" "$lr"; then or=""
      elif git -C "$root" merge-base --is-ancestor "$lr" "$or"; then lr=""
      elif [ "$(git -C "$root" log -1 --format=%ct "$or")" -gt "$(git -C "$root" log -1 --format=%ct "$lr")" ]; then lr=""
      else or=""; fi
    fi
    [ -z "$lr$or" ] || printf '%s\t%s\t%s\n' "$n" "${or:-$lr}" "$w"
  done
}

# changed_or_quiet <check>: the report text is on stdin. Returns 0 when its signature differs from the last run's (the
# caller reports), 1 when it is the same or empty (the caller stays quiet). Text that only ages, such as timestamps and
# "3 hours ago", is removed before the signature is taken, so a report that only got older stays quiet.
changed_or_quiet() {
  local check="$1" dir sigfile norm sig old
  [ -n "$check" ] || { echo "changed_or_quiet needs a check name" >&2; return 1; }
  dir="$(_chk_thrum_dir)" || return 1
  mkdir -p "$dir/results/checks-state" || { echo "cannot create $dir/results/checks-state" >&2; return 1; }
  sigfile="$dir/results/checks-state/$check.sig"
  norm="$(sed -E \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9:.]+Z?)?/<date>/g' \
    -e 's/[0-9]+ ?(seconds?|minutes?|hours?|days?|weeks?|secs?|mins?|hrs?)( ago)?/<age>/g' \
    -e 's/(^|[^[:alnum:]_])[0-9]+(s|m|h|d|w)([^[:alnum:]_]|$)/\1<age>\3/g' \
    -e 's/(^|[^[:alnum:]_])[0-9]+(s|m|h|d|w)([^[:alnum:]_]|$)/\1<age>\3/g' | tr -s ' \t' ' ' | sed -e '/^ *$/d')"
  if [ -z "$norm" ]; then
    sig="empty"
  else
    sig="$(printf '%s\n' "$norm" | cksum | tr -d ' ')"
  fi
  old=""
  if [ -f "$sigfile" ]; then old="$(cat "$sigfile")"; fi
  printf '%s\n' "$sig" > "$sigfile" || { echo "cannot write $sigfile" >&2; return 1; }
  if [ "$sig" = "empty" ] || [ "$sig" = "$old" ]; then
    return 1
  fi
  return 0
}

# write_report <check>: the report is on stdin. Overwrites <thrum>/results/reports/<check>.md, where <thrum> is the
# checkout's .thrum or the folder .thrum/redirect names.
write_report() {
  local check="$1" dir body
  [ -n "$check" ] || { echo "write_report needs a check name" >&2; return 1; }
  dir="$(_chk_thrum_dir)" || return 1
  body="$(cat)"
  mkdir -p "$dir/results/reports" || { echo "cannot create $dir/results/reports" >&2; return 1; }
  printf '%s\n' "$body" > "$dir/results/reports/$check.md.tmp" && mv "$dir/results/reports/$check.md.tmp" "$dir/results/reports/$check.md" \
    || { echo "cannot write $dir/results/reports/$check.md" >&2; return 1; }
  return 0
}

# fetch_or_report [remote]: a plain git fetch of the remote (default origin). It never removes a ref. On failure it
# prints one line and returns 1, so the caller can put the line in its report.
fetch_or_report() {
  local remote="${1:-origin}" err root
  root="$(_chk_root)" || return 1
  if err="$(git -C "$root" fetch "$remote" 2>&1)"; then
    return 0
  fi
  echo "FETCH FAILED: git fetch $remote: $(printf '%s' "$err" | head -n 1)" >&2
  return 1
}

# missing_notice <what> <skill> [key]: prints the missing-policy line and tells the coordinator, once per signature.
# <what> is a file under .thrum/policy/ or a thrum config key. A section recorded as skipped gets the wording of its
# reason. The signatures are kept in the "reported" list of .thrum/policy/onboarding.json; when that file does not
# exist the line is printed every time. Always returns 1: the step that needs the value stops.
missing_notice() {
  local what="$1" skill="$2" key="${3:-}" root ob sec status reason sig line keypart=""
  _chk_need_jq || return 1
  root="$(_chk_root)" || return 1
  ob="$root/$CHK_POLICY_REL/onboarding.json"
  [ -n "$key" ] && keypart=" [key $key]"
  sig="missing:${what#"$CHK_POLICY_REL"/}"
  [ -n "$key" ] && sig="$sig:$key"
  line="ONBOARDING MISSING: $what$keypart (written by $skill); run $skill"
  if [ -f "$ob" ]; then
    case "$skill" in
      onboarding-security) sec=S1 ;;
      project-philosophy) sec=S2 ;;
      onboarding-coupling) sec=S3 ;;
      onboarding-gates) sec=S4 ;;
      onboarding-checks) sec=S5 ;;
      onboarding-coordinator) sec=S6 ;;
      *) sec="" ;;
    esac
    if [ -n "$sec" ]; then
      status="$(jq -r --arg s "$sec" '.sections[$s].status // ""' "$ob")"
      reason="$(jq -r --arg s "$sec" '.sections[$s].reason // ""' "$ob")"
      if [ "$status" = "skipped" ]; then
        case "$reason" in
          owner) line="ONBOARDING MISSING: $what$keypart (owner-declined); run $skill to add it"; sig="skipped:$skill:owner" ;;
          profile) line="ONBOARDING MISSING: $what$keypart (skipped for the Solo profile; run $skill to add it)"; sig="skipped:$skill:profile" ;;
        esac
      fi
    fi
    if [ "$(jq -r --arg g "$sig" '(.reported // []) | index($g) // "none"' "$ob")" != "none" ]; then
      return 1
    fi
  fi
  echo "$line" >&2
  if [ -n "${CHK_COORDINATOR:-}" ]; then
    printf '%s\n' "$line" | thrum send --to "@$CHK_COORDINATOR" --stdin >/dev/null 2>&1 \
      || echo "could not message the coordinator $CHK_COORDINATOR" >&2
  fi
  if [ -f "$ob" ]; then
    jq --arg g "$sig" '.reported = ((.reported // []) + [$g])' "$ob" > "$ob.tmp" && mv "$ob.tmp" "$ob" \
      || echo "could not record the notice in $CHK_POLICY_REL/onboarding.json" >&2
  fi
  return 1
}

# This daemon's own ID: `daemon_id` from `thrum whoami --json`, read once per script run (the first deliver that needs
# it; the flag keeps every later call from asking again). Absent (an old-form daemon) it stays empty: no row is
# qualified and every row is local.
CHK_OWN_DAEMON_ID=""
CHK_OWN_DAEMON_ID_READ=0
_chk_own_daemon_id() {
  [ "$CHK_OWN_DAEMON_ID_READ" = 0 ] || return 0
  CHK_OWN_DAEMON_ID_READ=1
  CHK_OWN_DAEMON_ID="$(thrum whoami --json </dev/null 2>/dev/null | jq -r '.daemon_id // ""' 2>/dev/null)" || CHK_OWN_DAEMON_ID=""
}

# deliver [--full] [recipient]: the message is on stdin; CHECK_NAME (optional) names the check in a pane line. Sends to the
# recipient, or when none is given to CHK_DELIVER_TO, or when that is empty to the merge king of the merge target
# (orchestration.merge_kings[<target>]). With no merge king it calls missing_notice for orchestration.merge_kings and
# sends nothing. Uses the pane when the recipient has a live tmux session and CHK_DELIVERY is auto or pane; the inbox
# otherwise, and when the pane send fails. On the pane a report is cut to its first line plus the report-file pointer;
# --full sends the whole body instead, its lines joined by single spaces (one Enter submits all of it), with no pointer.
# The inbox always gets the whole body. Delivery does not depend on the install variant.
deliver() {
  local full=0 to body target kings state line rc=0 pick amb
  if [ "${1:-}" = "--full" ]; then
    full=1
    shift
  fi
  _chk_need_thrum || return 1
  to="${1:-${CHK_DELIVER_TO:-}}"
  body="$(cat)"
  if [ -z "${CHK_DELIVERY:-}" ]; then
    missing_notice "$CHK_POLICY_REL/checks.json" onboarding-checks delivery
    return 1
  fi
  if [ -z "$to" ]; then
    _chk_need_jq || return 1
    if [ -z "${CHK_MERGE_TARGET_FROM:-}" ]; then
      missing_notice "$CHK_POLICY_REL/checks.json" onboarding-checks merge_target_from
      return 1
    fi
    target="$(thrum config show "$CHK_MERGE_TARGET_FROM" --json 2>/dev/null | jq -r '.value // empty' 2>/dev/null)"
    kings="$(thrum config show orchestration.merge_kings --json 2>/dev/null | jq -r --arg t "$target" '(.value | if type == "string" then fromjson else . end)[$t] // empty' 2>/dev/null)"
    if [ -z "$target" ] || [ -z "$kings" ]; then
      missing_notice orchestration.merge_kings onboarding-gates
      return 1
    fi
    to="$kings"
  fi
  to="${to#@}"
  if [ "$CHK_DELIVERY" != "inbox" ]; then
    # tmux status rows are this daemon's sessions. A full ID (has "@") matches the row whose .agent equals it
    # (or .agent + "@" + .origin_daemon, or + this daemon's ID, when .agent is bare) and nothing else; a bare name
    # matches the row's name (.agent up to "@"). A session is local unless it names another daemon (agent without
    # "@", or its daemon half is this daemon, or origin_daemon empty or this daemon); local first, else the single
    # row elsewhere. A bare row `a` and a row `a@<this daemon>` are one agent. Several distinct agents under one
    # bare name pick nothing: the ambiguity is reported and the message goes to the inbox.
    _chk_own_daemon_id
    pick="$(thrum tmux status --json 2>/dev/null | jq -c --arg a "$to" --arg own "$CHK_OWN_DAEMON_ID" '
      [.sessions[]? | select(.state == "alive")
        | {n: .name, id: (.agent // ""), od: (.origin_daemon // "")}
        | .nm = (.id | split("@")[0])
        | .full = (if (.id | contains("@")) then .id elif .od != "" then (.id + "@" + .od) elif $own != "" then (.id + "@" + $own) else .id end)
        | .lcl = (((.id | contains("@")) | not) or ($own != "" and (.id | endswith("@" + $own))) or .od == "" or .od == $own)] as $s
      | (if ($a | contains("@")) then {l: [$s[] | select(.id == $a or .full == $a)], x: []}
         else ([$s[] | select(.nm == $a)]) as $c | {l: [$c[] | select(.lcl)], x: [$c[] | select(.lcl | not)]} end) as $g
      | ($g.l | map(.full) | unique) as $li
      | ($g.x | map(.full) | unique) as $xi
      | if ($li | length) == 1 then {name: $g.l[0].n, amb: []}
        elif ($li | length) > 1 then {name: "", amb: $li}
        elif ($xi | length) == 1 then {name: $g.x[0].n, amb: []}
        elif ($xi | length) > 1 then {name: "", amb: $xi}
        else {name: "", amb: []} end' 2>/dev/null)"
    state="$(printf '%s' "$pick" | jq -r '.name // empty' 2>/dev/null)"
    amb="$(printf '%s' "$pick" | jq -r '(.amb // []) | join(" ")' 2>/dev/null)"
    [ -z "$amb" ] || printf "ambiguous roster entry '%s': candidates %s\n" "$to" "$amb" >&2
    if [ -n "$state" ]; then
      if [ "$full" -eq 1 ]; then
        line="$(printf '%s\n' "$body" | sed -e '/^[[:space:]]*$/d' | paste -s -d ' ' -)"
      else
        line="$(printf '%s\n' "$body" | sed -e '/^[[:space:]]*$/d' | head -n 1 | cut -c 1-200)"
        line="[${CHECK_NAME:-check}] $line (report: .thrum/results/reports/${CHECK_NAME:-check}.md)"
      fi
      if thrum tmux send "$state" "$line" >/dev/null 2>&1; then
        return 0
      fi
      echo "pane send to $to failed; sending to the inbox" >&2
    fi
  fi
  printf '%s\n' "$body" | thrum send --to "@$to" --stdin >/dev/null 2>&1 || rc=1
  if [ "$rc" -ne 0 ]; then
    echo "could not send the message to $to" >&2
  fi
  return "$rc"
}
