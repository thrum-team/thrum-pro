#!/usr/bin/env bash
# Focused checks for to-thrum.sh with a fake thrum on PATH. No real daemon.
# The entitlement is the daemon's answer to a memory.edit probe, so the fake
# answers that probe from FAKE_PROBE (granted: "not found" for the probe ID;
# not granted: the license error). Tier names are not consulted.
# Covers: refusal before any change when not entitled, refusal when THRUM_REPO
# is unset, a granted create that verifies byte for byte, that a granted
# entitlement proceeds whatever the license tier, and the audience flag:
# --personal sets scope agent and tag personal, --box-wide sets scope project
# and tag indexed_in:runtime_memory, exactly one is required, and a reused
# record is not changed and gets a tagging hint.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/to-thrum-test.XXXXXX")"
trap 'rm -r "${TMP:?}"' EXIT

BIN="$TMP/bin"; LOG="$TMP/calls.log"; STORE="$TMP/store"
mkdir -p "$BIN" "$STORE" "$TMP/repo" "$TMP/memory"
export FAKE_LOG="$LOG" FAKE_STORE="$STORE"

# Fake thrum. memory edit (the probe) prints FAKE_PROBE_OUT. memory create
# stores the --full body and returns an ID. memory show prints the stored body.
cat > "$BIN/thrum" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$1 ${2:-}" in
  "memory edit")
    cat "$FAKE_PROBE_OUT" ;;
  "memory create")
    full=""; while [ $# -gt 0 ]; do [ "$1" = "--full" ] && { full="${2#@}"; break; }; shift; done
    cp "$full" "$FAKE_STORE/mem-1.body"; echo '{"id":"mem-1"}' ;;
  "memory show")
    cat "$FAKE_STORE/mem-1.body" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
FAKE
chmod +x "$BIN/thrum"

# Probe answers. "not found" means the gate passed; the license line means it did not.
printf 'Error: memory.edit: RPC error -32000: memory.edit: memory: not found: thrum-mem-entitlement-probe-000\n' > "$TMP/probe-granted"
printf 'Error: memory.substrate requires a license — run `thrum license` to activate\n' > "$TMP/probe-not-granted"

topic="$TMP/memory/topic.md"
printf -- '---\nname: topic\nmetadata:\n  type: feedback\n---\n\nRule body line one.\nRule body line two.\n' > "$topic"
before="$(cat "$topic")"
index="$TMP/memory/MEMORY.md"; printf -- '- index line\n' > "$index"; index_before="$(cat "$index")"

fail() { echo "FAIL: $*" >&2; exit 1; }
# run <probe-answer-file> <to-thrum.sh args...>: stdout and stderr merged.
run() { local probe="$1"; shift; PATH="$BIN:$PATH" FAKE_PROBE_OUT="$probe" THRUM_REPO="$TMP/repo" \
  bash "$SCRIPT_DIR/to-thrum.sh" "$@" 2>&1; }

# 1. Not entitled: exit 7, plain message, nothing changed, no create called.
: > "$LOG"
set +e
out="$(run "$TMP/probe-not-granted" "$topic" "before any change" --personal)"; rc=$?
set -e
[ "$rc" -eq 7 ] || fail "not-entitled exit was $rc, want 7"
printf '%s' "$out" | grep -q 'needs Thrum Pro (free for eligible public repositories)' || fail "missing Pro message"
[ "$(cat "$topic")" = "$before" ] || fail "topic file changed while not entitled"
[ "$(cat "$index")" = "$index_before" ] || fail "index changed while not entitled"
grep -q 'memory create' "$LOG" && fail "memory create ran while not entitled"

# 2. THRUM_REPO unset: refuse with exit 2 and change nothing.
set +e
PATH="$BIN:$PATH" FAKE_PROBE_OUT="$TMP/probe-granted" env -u THRUM_REPO \
  bash "$SCRIPT_DIR/to-thrum.sh" "$topic" "x" --personal >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "unset THRUM_REPO exit was $rc, want 2"

# 3. Entitled: create, verify byte for byte, and add thrum_memory to frontmatter.
id="$(run "$TMP/probe-granted" "$topic" "when the rule applies" --personal)"
[ "$id" = "mem-1" ] || fail "id was [$id], want mem-1"
grep -q '^  thrum_memory: mem-1$' "$topic" || fail "thrum_memory not written to frontmatter"
[ "$(cat "$index")" = "$index_before" ] || fail "index changed by the helper"

# 4. The tier does not matter: an entitled probe proceeds for any license tier.
#    The fake ignores the tier, so this checks that the helper does not read it.
topic2="$TMP/memory/topic2.md"
printf -- '---\nname: topic2\nmetadata:\n  type: feedback\n---\n\nSecond rule body.\n' > "$topic2"
id2="$(run "$TMP/probe-granted" "$topic2" "granted under any tier" --personal)"
[ -n "$id2" ] || fail "granted entitlement did not create a record"

# 5. --personal: scope agent, tag personal, claude-memory kept, no box-wide tag.
topic3="$TMP/memory/topic3.md"
printf -- '---\nname: topic3\nmetadata:\n  type: feedback\n---\n\nPersonal rule body.\n' > "$topic3"
: > "$LOG"
run "$TMP/probe-granted" "$topic3" "when the personal rule applies" --personal >/dev/null
create_line="$(grep '^memory create' "$LOG")" || fail "personal: memory create did not run"
case "$create_line" in *"--scope agent "*) ;; *) fail "personal: scope was not agent: $create_line" ;; esac
case "$create_line" in *"--tag personal "*) ;; *) fail "personal: tag personal missing: $create_line" ;; esac
case "$create_line" in *"--tag claude-memory "*) ;; *) fail "personal: tag claude-memory missing: $create_line" ;; esac
case "$create_line" in *indexed_in*) fail "personal: record carries the box-wide tag: $create_line" ;; esac

# 6. --box-wide, flag in the first position and a kind: scope project, tag
#    indexed_in:runtime_memory, claude-memory kept, no personal tag.
topic4="$TMP/memory/topic4.md"
printf -- '---\nname: topic4\nmetadata:\n  type: feedback\n---\n\nBox-wide rule body.\n' > "$topic4"
: > "$LOG"
run "$TMP/probe-granted" --box-wide "$topic4" "when the box-wide rule applies" lesson >/dev/null
create_line="$(grep '^memory create' "$LOG")" || fail "box-wide: memory create did not run"
case "$create_line" in *"--kind lesson "*) ;; *) fail "box-wide: kind was not lesson: $create_line" ;; esac
case "$create_line" in *"--scope project "*) ;; *) fail "box-wide: scope was not project: $create_line" ;; esac
case "$create_line" in *"--tag indexed_in:runtime_memory "*) ;; *) fail "box-wide: tag indexed_in:runtime_memory missing: $create_line" ;; esac
case "$create_line" in *"--tag claude-memory "*) ;; *) fail "box-wide: tag claude-memory missing: $create_line" ;; esac
case "$create_line" in *"--tag personal"*) fail "box-wide: record carries the personal tag: $create_line" ;; esac

# 7. Exactly one audience flag. Neither, both and an unknown option exit 2 with
#    no thrum call and no file change; the same topic with one flag succeeds.
topic5="$TMP/memory/topic5.md"
printf -- '---\nname: topic5\nmetadata:\n  type: feedback\n---\n\nAudience rule body.\n' > "$topic5"
before5="$(cat "$topic5")"
: > "$LOG"
set +e
out="$(run "$TMP/probe-granted" "$topic5" "no audience")"; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "no audience flag: exit was $rc, want 2"
printf '%s' "$out" | grep -q 'pass exactly one of --personal or --box-wide' || fail "no audience flag: missing message: $out"
set +e
out="$(run "$TMP/probe-granted" "$topic5" "both audiences" --personal --box-wide)"; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "both audience flags: exit was $rc, want 2"
printf '%s' "$out" | grep -q 'use exactly one of --personal or --box-wide' || fail "both audience flags: missing message: $out"
set +e
out="$(run "$TMP/probe-granted" "$topic5" "bad option" --personal --bogus)"; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "unknown option: exit was $rc, want 2"
printf '%s' "$out" | grep -q 'unknown option: --bogus' || fail "unknown option: missing message: $out"
[ ! -s "$LOG" ] || fail "thrum was called although the audience flags were invalid: $(cat "$LOG")"
[ "$(cat "$topic5")" = "$before5" ] || fail "topic file changed although the audience flags were invalid"
id5="$(run "$TMP/probe-granted" "$topic5" "one audience flag" --personal)"
[ "$id5" = "mem-1" ] || fail "control: one audience flag gave [$id5], want mem-1"

# 8. A topic file that already names a record: the record is reused, no create
#    runs, stdout is the ID only, and stderr names the edit command that adds
#    the tag.
topic6="$TMP/memory/topic6.md"
printf -- '---\nname: topic6\nmetadata:\n  thrum_memory: mem-1\n---\n\nReuse body.\n' > "$topic6"
printf 'Reuse body.\n' > "$STORE/mem-1.body"
: > "$LOG"
PATH="$BIN:$PATH" FAKE_PROBE_OUT="$TMP/probe-granted" THRUM_REPO="$TMP/repo" \
  bash "$SCRIPT_DIR/to-thrum.sh" "$topic6" "when reuse applies" --personal >"$TMP/reuse.out" 2>"$TMP/reuse.err"
[ "$(cat "$TMP/reuse.out")" = "mem-1" ] || fail "reuse: stdout was [$(cat "$TMP/reuse.out")], want mem-1"
grep -q 'thrum memory edit mem-1 --add-tag personal' "$TMP/reuse.err" || fail "reuse: no tagging hint: $(cat "$TMP/reuse.err")"
grep -q '^memory create' "$LOG" && fail "reuse: memory create ran for an existing record"
PATH="$BIN:$PATH" FAKE_PROBE_OUT="$TMP/probe-granted" THRUM_REPO="$TMP/repo" \
  bash "$SCRIPT_DIR/to-thrum.sh" --box-wide "$topic6" "when reuse applies" >/dev/null 2>"$TMP/reuse2.err"
grep -q 'thrum memory edit mem-1 --add-tag indexed_in:runtime_memory' "$TMP/reuse2.err" || fail "reuse: no box-wide tagging hint: $(cat "$TMP/reuse2.err")"

echo "PASS: to-thrum.sh refuses when memory.substrate is not granted (no change), proceeds when it is, and tags by audience"
