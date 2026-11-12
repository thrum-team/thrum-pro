#!/usr/bin/env bash
# to-thrum.sh <topic-file.md> <trigger> [kind] --personal|--box-wide
# Copies the topic file's body (after the frontmatter) into a thrum memory
# record unchanged, verifies it byte for byte, adds thrum_memory: <ID> to the
# file's frontmatter metadata, and prints the ID. Reuses an existing ID if the
# file already has thrum_memory set. Never deletes anything.
#
# Exactly one of --personal or --box-wide is required (any position). --personal
# creates the record with --scope agent and --tag personal: the agent's own
# memory, delivered by the personal block, no shared index line. --box-wide
# creates it with --scope project and --tag indexed_in:runtime_memory: a memory
# every agent on the machine needs, with a line in the shared index. The two
# tags are exclusive. The claude-memory tag is kept on both.
#
# Runtime- and box-neutral: no paths are hard-coded. The memory directory is
# the topic file's directory and the index is <memory dir>/MEMORY.md (the
# caller edits the index; this script never does). The thrum repo must be set
# with THRUM_REPO, because thrum finds its daemon from the current directory.
#
# Licensing: `thrum memory create` needs the memory.substrate entitlement. The
# helper probes that entitlement through the daemon before reading or writing
# anything. Without it the helper exits 7 with a plain message and changes nothing.
set -euo pipefail
usage() { echo "usage: to-thrum.sh <topic-file.md> <trigger> [agent_rule|lesson] --personal|--box-wide" >&2; exit 2; }
audience=""; npos=0; pos0=""; pos1=""; pos2=""
for a in "$@"; do
  case "$a" in
    --personal|--box-wide)
      [ -z "$audience" ] || [ "$audience" = "$a" ] || { echo "use exactly one of --personal or --box-wide" >&2; exit 2; }
      audience="$a" ;;
    --*) echo "unknown option: $a" >&2; usage ;;
    *)
      case "$npos" in 0) pos0="$a" ;; 1) pos1="$a" ;; 2) pos2="$a" ;; *) usage ;; esac
      npos=$((npos + 1)) ;;
  esac
done
[ "$npos" -ge 2 ] || usage
[ -n "$audience" ] || { echo "pass exactly one of --personal or --box-wide" >&2; usage; }
f="$pos0"; trigger="$pos1"; kind="${pos2:-agent_rule}"
if [ "$audience" = "--personal" ]; then
  scope="agent"; audience_tag="personal"; reuse_note=""
else
  scope="project"; audience_tag="indexed_in:runtime_memory"; reuse_note=" A tag does not change scope: an agent-scoped record cannot become box-wide, so create a new record with --box-wide."
fi
[ -f "$f" ] || { echo "no file: $f" >&2; exit 2; }
f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
repo="${THRUM_REPO:-}"
[ -n "$repo" ] && [ -d "$repo" ] || { echo "set THRUM_REPO to the thrum repo root" >&2; exit 2; }

# Entitlement, checked by the daemon, not by tier name. memory.edit runs the
# memory.substrate gate as its first statement, so an edit of a nonexistent ID
# returns "not found" only when the feature is granted, and the license error
# otherwise. Nothing is written by the probe. Fail closed: proceed only on
# "not found" for the probe ID.
probe="$(cd "$repo" && thrum memory edit thrum-mem-entitlement-probe-000 --oneline probe 2>&1 || true)"
if ! printf '%s\n' "$probe" | grep -q 'memory: not found: thrum-mem-entitlement-probe-000'; then
  echo "needs Thrum Pro (free for eligible public repositories)" >&2
  echo "not changed: $f" >&2
  exit 7
fi

[ "${#trigger}" -le 200 ] || { echo "trigger over 200 chars" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -r "${tmp:?}"' EXIT
# body = everything after the second '---' line, minus one leading blank line
awk 'BEGIN{n=0} /^---$/ && n<2 {n++; next} n>=2{print}' "$f" | awk 'NR==1 && $0=="" {next} {print}' > "$tmp/body.md"
[ -s "$tmp/body.md" ] || { echo "empty body: $f" >&2; exit 3; }
id="$(awk '/^  thrum_memory: /{print $2; exit}' "$f")"
cd "$repo"
if [ -z "$id" ]; then
  out="$(thrum memory create --kind "$kind" --scope "$scope" --title "$(basename "$f" .md)" \
    --oneline "$trigger" --full @"$tmp/body.md" --tag claude-memory --tag "$audience_tag" --json)"
  id="$(printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("id") or d.get("record",{}).get("id",""))')"
  [ -n "$id" ] || { echo "create gave no id: $out" >&2; exit 4; }
else
  echo "reusing $id: its tags and scope are unchanged. To set the tag: thrum memory edit $id --add-tag $audience_tag.$reuse_note" >&2
fi
thrum memory show "$id" --format body --zoom full > "$tmp/back.md"
if ! cmp -s "$tmp/body.md" "$tmp/back.md"; then
  echo "MISMATCH for $f ($id); index NOT to be changed" >&2
  diff "$tmp/body.md" "$tmp/back.md" | head -5 >&2
  exit 5
fi
if ! grep -q '^  thrum_memory: ' "$f"; then
  awk -v id="$id" '{print} /^metadata:[[:space:]]*$/ && !done {print "  thrum_memory: " id; done=1}' "$f" > "$tmp/new.md"
  grep -q "thrum_memory: $id" "$tmp/new.md" || { echo "no metadata: block in $f; add thrum_memory by hand" >&2; echo "$id"; exit 6; }
  cat "$tmp/new.md" > "$f"
fi
echo "$id"
