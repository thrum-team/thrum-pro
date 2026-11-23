#!/usr/bin/env bash
# Suggests how often the checks should run, from how often work lands. Counts first-parent commits on the merge target
# over the last 30 days, as landings per week: 35 or more is 4 hours, 15 to 34 is 8 hours, fewer is 24 hours, and fewer
# than 10 landings in the window is 24 hours. Prints the hours on stdout and the basis on stderr. Run it from the
# checkout. Needs: git, thrum, awk; jq when checks.json exists. Bash 3.2 safe. Calls no bare timeout.
#
# The merge target is the branch named by the thrum config key in checks.json merge_target_from. onboarding-checks runs
# this before it has written checks.json, so with no checks.json (or no such key) the key is orchestration.merge_target,
# the same value the schema offers. The branch is read locally first, then as origin/<branch>.
#
# Env (test seams): CHECKS_ROOT the checkout root (default: git rev-parse --show-toplevel); CHECKS_NOW the current time
# in epoch seconds (default: date +%s).
# Exit: 0 with the hours printed; 1 when no suggestion could be made, with the reason on stderr.
set -u

root="${CHECKS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$root" ] || { echo "not inside a git checkout" >&2; exit 1; }
now="${CHECKS_NOW:-$(date +%s)}"

key=orchestration.merge_target
file="$root/.thrum/policy/checks.json"
if [ -f "$file" ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required to read $file and was not found" >&2; exit 1; }
  k="$(jq -r '.merge_target_from // ""' "$file" 2>/dev/null)" || { echo "$file is not valid JSON" >&2; exit 1; }
  [ -n "$k" ] && key="$k"
fi

target="$(thrum config show "$key" --json 2>/dev/null | jq -r '.value // empty' 2>/dev/null)"
[ -n "$target" ] || { echo "thrum config key $key has no value, so the merge target is unknown" >&2; exit 1; }

ref=""
for c in "$target" "origin/$target"; do
  if git -C "$root" rev-parse --verify -q "$c^{commit}" >/dev/null 2>&1; then ref="$c"; break; fi
done
[ -n "$ref" ] || { echo "the merge target $target is not a branch here or on origin" >&2; exit 1; }

since=$((now - 30 * 86400))
count="$(git -C "$root" log --first-parent --format=%ct "$ref" | awk -v s="$since" '$1 >= s { n++ } END { print n + 0 }')" \
  || { echo "git log failed on $ref" >&2; exit 1; }

# Per week = count * 7 / 30; compare count * 7 with the threshold * 30 to stay in whole numbers.
if [ "$count" -lt 10 ]; then
  hours=24
elif [ $((count * 7)) -ge $((35 * 30)) ]; then
  hours=4
elif [ $((count * 7)) -ge $((15 * 30)) ]; then
  hours=8
else
  hours=24
fi
echo "basis: $count landings on $ref in the last 30 days" >&2
echo "$hours"
