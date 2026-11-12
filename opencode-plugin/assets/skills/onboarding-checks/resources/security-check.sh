#!/usr/bin/env bash
# Security check: reports watch-list hits in what landed on the merge target and in unmerged branches, each labelled landed or
# on branch NAME, once each (results/checks-state/security.seen), with each hit's enclosing function. The watch list is the `onboarding-watch-list` block of the security model (checks.json key
# security_doc). Run it from the checkout; it sources lib.sh from its own directory. Needs: jq, git, awk, thrum. Bash 3.2
# safe. Calls no bare timeout. It never changes a branch or a ref: its fetch is a plain `git fetch`.
#
# It refuses, says why once, and exits 1 when the security model has no watch-list block, the block does not say
# `non_goals_confirmed: true`, the watch list is empty, or a pattern is not a valid extended regex. A missing security
# model is a miss handled by missing_notice.
# A hit is an added line that matches a watch pattern (extended regex, first match on the line). Hits in files that match
# checks.json test_globs, and in the security model and .thrum/policy/ themselves, are dropped. So are hits inside a
# comment or a string literal, judged by a line heuristic, unless CHECKS_SECURITY_INCLUDE_LITERALS=1.
# The enclosing function is the nearest earlier line of the `git diff -W` hunk that starts in column 0 with a letter, `_`
# or `$`, which is git's own default function-start rule.
#
# Env (test seams): CHECKS_NOW is the current time in epoch seconds (default: date +%s).
# Exit: 0 after a run (a report was sent, or nothing to report); 1 when the run could not be done, with the reason on stderr.
# shellcheck disable=SC1091  # lib.sh is found at run time, next to this file
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
. "$HERE/lib.sh"

CHECK_NAME=security
export CHECK_NAME

root="$(_chk_root)" || exit 1
[ -n "$root" ] || { echo "not inside a git checkout" >&2; exit 1; }
load_config || exit 1

now="${CHECKS_NOW:-$(date +%s)}"
tdir="$(_chk_thrum_dir)" || exit 1
state="$tdir/results/checks-state"
mkdir -p "$state" || { echo "cannot create $state" >&2; exit 1; }
stamp="$state/security.delivered"
refused="$state/security.refused"

doc="$root/$CHK_SECURITY_DOC"
if [ ! -f "$doc" ]; then
  missing_notice "$CHK_SECURITY_DOC" onboarding-security
  exit 1
fi

# refuse REASON: say why once (until the reason changes), tell the coordinator, and stop.
refuse() {
  local reason="$1" line
  if [ -f "$refused" ] && [ "$(cat "$refused")" = "$reason" ]; then
    exit 1
  fi
  line="SECURITY CHECK REFUSED: $reason"
  echo "$line" >&2
  if [ -n "${CHK_COORDINATOR:-}" ]; then
    printf '%s\n' "$line" | thrum send --to "@$CHK_COORDINATOR" --stdin >/dev/null 2>&1 \
      || echo "could not message the coordinator $CHK_COORDINATOR" >&2
  fi
  printf '%s\n' "$reason" > "$refused" || echo "cannot write $refused" >&2
  exit 1
}

# The watch list: the first onboarding-watch-list block of the security model.
parsed="$(awk '
  BEGIN { q39 = sprintf("%c", 39) }
  function val(s,   q, out, i, c, n) {
    sub(/^[ \t]+/, "", s)
    q = substr(s, 1, 1)
    out = ""
    if (q == "\"") {
      for (i = 2; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") { n = substr(s, i + 1, 1); if (n == "\\" || n == "\"") { out = out n; i++ } else out = out c }
        else if (c == "\"") break
        else out = out c
      }
      return out
    }
    if (q == q39) {
      for (i = 2; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == q39) { if (substr(s, i + 1, 1) == q39) { out = out q39; i++ } else break }
        else out = out c
      }
      return out
    }
    sub(/[ \t]+#.*$/, "", s); sub(/[ \t\r]+$/, "", s)
    return s
  }
  function flushitem() { if (have) printf "P\t%s\t%s\n", pat, why; have = 0 }
  !done && !inb && /^```yaml[ \t]+onboarding-watch-list[ \t]*\r?$/ { inb = 1; found = 1; next }
  inb && /^```[ \t]*\r?$/ { flushitem(); inb = 0; done = 1; next }
  inb {
    s = $0
    if (s ~ /^[ \t]*non_goals_confirmed:/) { sub(/^[ \t]*non_goals_confirmed:/, "", s); confirmed = val(s); next }
    if (s ~ /^[ \t]*-[ \t]+pattern:/) { flushitem(); sub(/^[ \t]*-[ \t]+pattern:/, "", s); pat = val(s); why = ""; have = 1; next }
    if (s ~ /^[ \t]*why:/) { sub(/^[ \t]*why:/, "", s); why = val(s); next }
  }
  END { flushitem(); printf "FOUND\t%s\nCONFIRMED\t%s\n", found + 0, confirmed }
' "$doc")" || { echo "could not read $CHK_SECURITY_DOC" >&2; exit 1; }

[ "$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "FOUND" { print $2 }')" = "1" ] \
  || refuse "$CHK_SECURITY_DOC has no onboarding-watch-list block, so there is nothing to watch for; run onboarding-security to write it"
[ "$(printf '%s\n' "$parsed" | awk -F'\t' '$1 == "CONFIRMED" { print $2 }')" = "true" ] \
  || refuse "the watch list in $CHK_SECURITY_DOC does not say non_goals_confirmed: true, so no non-goal is confirmed; run onboarding-security to confirm one"
patfile="$state/security.patterns"
printf '%s\n' "$parsed" | awk -F'\t' '$1 == "P" { print $2 "\t" $3 }' > "$patfile" || exit 1
[ -s "$patfile" ] || refuse "the watch list in $CHK_SECURITY_DOC has no patterns; run onboarding-security to add them"
while IFS="$(printf '\t')" read -r p _; do
  printf '' | grep -E -e "$p" >/dev/null 2>&1
  if [ "$?" -eq 2 ]; then
    refuse "the watch pattern '$p' in $CHK_SECURITY_DOC is not a valid extended regex; run onboarding-security to fix it"
  fi
done < "$patfile"
rm -f "$refused"

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

# The diff base: the newest first-parent commit older than the window (the empty tree when there is none).
base="$(git -C "$root" log --first-parent --format='%H %ct' "$trunk_ref" | awk -v w="$window_start" '$2 < w { print $1; exit }')"
[ -n "$base" ] || base="$(git -C "$root" hash-object -t tree /dev/null)"

nl='
'

# Reads the diff on stdin and the pattern file (regex TAB why) as its first argument; prints one block per hit.
IFS= read -r -d '' awk_prog <<'AWK' || true
function noise(line, pos,   t, st, i, c) {
  t = line; sub(/^[ \t]+/, "", t)
  if (t ~ /^(\/\/|\/\*|\*|#|<!--)/) return 1
  st = ""
  for (i = 1; i < pos; i++) {
    c = substr(line, i, 1)
    if (st == "") {
      if (c == "\"" || c == "\047" || c == "`") st = c
      else if (c == "/" && substr(line, i + 1, 1) == "/") return 1
      else if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) return 1
    } else if (c == "\\") i++
    else if (c == st) st = ""
  }
  return (st != "")
}
function clip(s) { return length(s) > 160 ? substr(s, 1, 160) "..." : s }
function flush(   i, k, line, j, fn, from) {
  for (i = 1; i <= nl; i++) {
    if (substr(L[i], 1, 1) != "+") continue
    line = substr(L[i], 2)
    for (k = 1; k <= np; k++) {
      if (!match(line, RE[k])) continue
      if (ENVIRON["KEEP"] != "1" && noise(line, RSTART)) continue
      fn = ""
      for (j = i; j >= 1; j--) if (substr(L[j], 2, 1) ~ /^[A-Za-z_$]/) { fn = substr(L[j], 2); break }
      if (fn == "") fn = "(no enclosing function found)"
      printf "- %s: in %s [watch: %s] (%s)\n", file, clip(fn), WHY[k], ENVIRON["LABEL"]
      from = i - 2; if (from < 1) from = 1
      for (j = from; j < i; j++) printf "    | %s\n", clip(substr(L[j], 2))
      printf "    + %s\n", clip(line)
      break
    }
  }
  nl = 0
}
NR == FNR { np++; RE[np] = $1; WHY[np] = $2; next }
/^diff --git / { flush(); inhunk = 0; next }
!inhunk && /^\+\+\+ / { file = substr($0, 7); if ($0 ~ /^\+\+\+ \/dev\/null/) file = ""; next }
/^@@/ { flush(); inhunk = 1; next }
inhunk && file != "" && !/^\\/ { L[++nl] = $0 }
END { flush() }
AWK

# scan_hits LABEL DIFF-ARGS...: hits in `git diff DIFF-ARGS`, labelled LABEL; test files, the security model and policy folder skipped.
scan_hits() {
  local label="$1" f files names diff
  shift
  files=()
  names="$(git -C "$root" -c core.quotepath=false diff --name-only "$@")" || return 1
  while read -r f; do
    [ -n "$f" ] || continue
    case "$f" in "$CHK_SECURITY_DOC" | "$CHK_POLICY_REL"/*) continue ;; esac
    is_test_file "$f" || files[${#files[@]}]="$f"
  done <<EOF2
$names
EOF2
  [ "${#files[@]}" -gt 0 ] || return 0
  diff="$(git -C "$root" -c core.quotepath=false --literal-pathspecs diff -W --no-color --no-ext-diff "$@" -- "${files[@]}")" || return 1
  printf '%s\n' "$diff" | LABEL="$label" KEEP="${CHECKS_SECURITY_INCLUDE_LITERALS:-0}" awk -F'\t' "$awk_prog" "$patfile" -
}

# A diff that cannot be made is named on stderr and fails the run at the end; the other scans still run and report.
scanfail=0
hits="$(scan_hits landed "$base" "$trunk_ref")" || { echo "could not scan the diff on $trunk" >&2; scanfail=1; hits=""; }
origin_gone_load
while IFS="$(printf '\t')" read -r b ref _; do
  [ -n "$b" ] && [ "$(git -C "$root" rev-list --count "$trunk_ref..$ref")" -gt 0 ] || continue
  out="$(scan_hits "on branch $b" "$trunk_ref...$ref")" || { echo "could not scan the diff on $b" >&2; scanfail=1; continue; }
  [ -z "$out" ] || hits="$hits${hits:+$nl}$out"
done <<EOF2
$(branch_list)
EOF2

fetch_rows=""
[ -n "$fetch_line" ] && fetch_rows="- $fetch_line$nl"

# Each hit is reported once: keys (label, file, function, matched text; no line numbers) of the last sent report are in
# security.seen. A report goes out only when a current hit is not there; a run that only lost hits sends nothing.
seen="$state/security.seen"
keys="$(printf '%s\n' "$hits" | awk '/^- / { h = $0 } /^    \+ / { print h "\t" $0 }')"
sf="$seen"; [ -f "$sf" ] || sf=/dev/null
if [ -z "$hits" ] || ! printf '%s\n' "$keys" | grep -qvxF -f "$sf"; then
  printf '%s\n' "$keys" | sed -e '/^$/d' > "$seen" || true
  echo "security-check: nothing new to report"
  exit "$scanfail"
fi

# portable-ok: date -d is the GNU form; the BSD form -r follows it and the epoch is the last fallback
window_date="$(date -u -d "@$window_start" '+%Y-%m-%d %H:%M' 2>/dev/null || date -u -r "$window_start" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$window_start")"
n_hits="$(printf '%s\n' "$hits" | grep -c '^- ')"
report="Security check: $n_hits watch-list hit(s) (landed on $trunk, or on branches not merged yet) need a look
window: since $window_date UTC (at most $CHK_CADENCE_HOURS hours)
"
[ -n "$fetch_rows" ] && report="$report${nl}Fetch:$nl$fetch_rows"
report="$report${nl}Hits (added lines that match the watch list in $CHK_SECURITY_DOC):$nl$hits"

if printf '%s\n' "$report" | deliver; then
  printf '%s\n' "$report" | write_report security || true
  printf '%s\n' "$now" > "$stamp"
  printf '%s\n' "$keys" > "$seen" || true
  echo "security-check: report delivered"
  exit "$scanfail"
fi
# Delivery failed (the lib has said why): security.seen stays as it was, so the next run tries again.
exit 1
