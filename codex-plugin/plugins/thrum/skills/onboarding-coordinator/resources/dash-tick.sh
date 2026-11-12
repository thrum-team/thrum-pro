#!/usr/bin/env bash
# The coordinator's dash tick: runs the dashboard generator when checks.json names one, then delivers one prompt to the
# checks.json coordinator. The prompt follows the installed variant (onboarding.json variant.value). Run it from the
# checkout. Needs: jq, git, thrum. Bash 3.2 safe. Calls no bare timeout. It sources lib.sh from its own directory; both
# live in .thrum/policy/checks/ once installed.
#
# Licence change: each tick derives the variant from a fresh `thrum license status --json` (pro when repo_capabilities
# holds queue.write, state.write and memory.substrate; free otherwise, and free when the command fails) and compares it
# with variant.value. A difference adds one line to the prompt, once per change signature in `reported`. It never
# switches the variant itself.
#
# A missing checks.json, onboarding.json or variant.value is a miss: missing_notice reports it once and the tick stops
# without sending a prompt.
# Env (test seam): CHECKS_ROOT the checkout root (default: git rev-parse --show-toplevel).
# Exit: 0 when the prompt was delivered; 1 otherwise, with the reason on stderr.
set -u

# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1

load_config || exit 1
root="$(_chk_root)" || exit 1
[ -n "$root" ] || { echo "not inside a git checkout" >&2; exit 1; }
ob="$root/$CHK_POLICY_REL/onboarding.json"

if [ ! -f "$ob" ]; then
  missing_notice "$CHK_POLICY_REL/onboarding.json" onboarding-coordinator
  exit 1
fi
if ! jq -e 'type == "object"' "$ob" >/dev/null 2>&1; then
  echo "$CHK_POLICY_REL/onboarding.json is not a JSON object; run onboarding-coordinator to rewrite it" >&2
  exit 1
fi
recorded="$(jq -r '.variant.value // ""' "$ob")"
case "$recorded" in
  pro | free) ;;
  '')
    missing_notice "$CHK_POLICY_REL/onboarding.json" onboarding-coordinator variant.value
    exit 1
    ;;
  *)
    echo "$CHK_POLICY_REL/onboarding.json key variant.value must be pro or free, found: $recorded; run onboarding-coordinator" >&2
    exit 1
    ;;
esac

if [ -n "$CHK_DASHBOARD_GENERATOR" ]; then
  (cd "$root" && bash -c "$CHK_DASHBOARD_GENERATOR") >/dev/null \
    || echo "the dashboard generator failed: $CHK_DASHBOARD_GENERATOR" >&2
fi

derived="$(thrum license status --json 2>/dev/null | jq -r '
  (.repo_capabilities | if type == "array" then . else [] end) as $c
  | if (["queue.write", "state.write", "memory.substrate"] - $c | length) == 0 then "pro" else "free" end' 2>/dev/null)" || derived=free
[ "$derived" = pro ] || derived=free

if [ "$recorded" = pro ]; then
  prompt="Reconcile your queue, rewrite personal_state current_state and next_actions, dispatch anything idle; ask the owner any open owner question (dashboard, or Owner questions in .thrum/policy/worklist.md); reply only if an owner decision is needed."
else
  prompt="Reconcile .thrum/policy/worklist.md, rewrite .thrum/results/coordinator-state.md, dispatch anything idle; ask the owner any open item under Owner questions."
fi

sig=""
if [ "$derived" != "$recorded" ]; then
  sig="licence-change:$recorded->$derived"
  if [ "$(jq -r --arg g "$sig" '(.reported // []) | index($g) // "none"' "$ob")" = none ]; then
    prompt="$prompt
Your licence changed; run onboarding-coordinator to switch."
  else
    sig=""
  fi
fi

if ! printf '%s\n' "$prompt" | CHECK_NAME=dash-tick deliver --full "$CHK_COORDINATOR"; then
  echo "dash tick: the prompt was not delivered to $CHK_COORDINATOR" >&2
  exit 1
fi
if [ -n "$sig" ]; then
  jq --arg g "$sig" '.reported = ((.reported // []) + [$g])' "$ob" > "$ob.tmp" && mv "$ob.tmp" "$ob" \
    || echo "could not record the notice in $CHK_POLICY_REL/onboarding.json" >&2
fi
exit 0
