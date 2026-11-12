---
name: memory-to-thrum-pointer
description:
  "Use when MEMORY.md is near or over its read limit, or when adding a new
  memory entry. Moves an entry's full text into a thrum memory record and
  shrinks its index line to a trigger plus the thrum memory ID, with a
  byte-for-byte check."
# source: claude-plugin/skills/memory-to-thrum-pointer/SKILL.md
---

## Memory to thrum pointer

### Why

An index line that restates a rule goes wrong when it is shortened, because
shortening drops the scope that makes the rule true. An index line written as a
TRIGGER cannot contradict the rule, because it does not state the rule. It only
tells you when to read the full text.

So each entry has three parts:

- **Full text:** the topic file's body, copied unchanged into a thrum memory
  record (`--full`). This is the source to read before acting.
- **Trigger:** one line saying WHEN it applies, never WHAT it says. It goes in
  the record's `--oneline` field and in the index.
- **Topic file:** kept as the local copy. Never delete it.

Index line format, under ~140 characters:

```text
- 🔴 <trigger: when this applies> → `thrum-mem-<ID>`
```

The topic file carries `thrum_memory: <ID>` in its frontmatter; find it with
`grep -l 'thrum_memory: <ID>' <memory dir>/*.md`.

Keep the 🔴 only on entries that already have it.

### Personal or box-wide

Decide this first, for each entry. The two tags are exclusive: a record carries
one of them.

| The entry is                                   | Helper flag  | Tag                         | Scope     | Index line               |
| ---------------------------------------------- | ------------ | --------------------------- | --------- | ------------------------ |
| Yours alone: your own habits and working notes | `--personal` | `personal`                  | `agent`   | none                     |
| Needed by every agent on this machine          | `--box-wide` | `indexed_in:runtime_memory` | `project` | yes, in the shared index |

- A `personal` memory reaches you in the personal block that `thrum prime`
  writes at session start. Add no index line for it. An index line that already
  exists for the entry stays as it is, unless an index report names it.
- A box-wide memory reaches agents through its index line, so the line is
  required.
- A record that carries both tags is treated as `personal`: an index report
  never asks for a line for it.
- A record keeps the scope it was created with. Tag an existing one with
  `thrum memory edit <ID> --add-tag personal`. A tag does not change scope: an
  agent-scoped record cannot become box-wide, so create a new record for it.

### Writing the trigger

Name the situation or action that should make you read the rule, for example
"before choosing a model for any role" or "when the email bridge decides which
inbound mail it processes". Do not put the rule's answer in the trigger: no
"always", "never", "X not Y" or numbers. If the answer leaks in, it will drift
from the full text.

Test it by asking: if I were about to take the wrong action, would this line
make me stop and read? If not, name the action more concretely.

### Steps for one entry

Use the helper for steps 1 to 5. Run it from any directory with
`THRUM_REPO=<repo>` set to the thrum repo root (the helper runs thrum from
there). It extracts the body, creates or reuses the record, checks it byte for
byte, writes `thrum_memory` into the frontmatter, and prints the ID. It exits
non-zero on any problem, and then you leave that index line alone.

```bash
bash <skill-dir>/resources/to-thrum.sh <topic-file.md> "<trigger>" [agent_rule|lesson] --personal
bash <skill-dir>/resources/to-thrum.sh <topic-file.md> "<trigger>" [agent_rule|lesson] --box-wide
```

Pass exactly one of `--personal` or `--box-wide`. Without one the helper exits 2
and changes nothing. It sets the tag and scope from the table above and keeps
the `claude-memory` tag. When the topic file already names a record, the helper
reuses it, changes nothing on it, and prints the `thrum memory edit` command
that adds the tag.

Then do step 6 by hand. The manual steps below are what the helper does.

1. Read the topic file. Its body (everything after the frontmatter) is the full
   text.
2. Check whether a thrum memory already holds that text. Search with
   `thrum memory search` on a distinctive phrase. If the topic file names a
   `thrum-mem-` ID, `thrum memory show <ID> --format body --zoom full` and
   compare.
3. If there is none, create one. Write the body to a scratch file first, then
   pass it with `@file`, so the shell never rewrites it:

   ```bash
   # personal
   thrum memory create --kind agent_rule --scope agent \
     --title "<topic file name>" --oneline "<trigger>" \
     --full @"$SCRATCH/body.md" --tag claude-memory --tag personal --json

   # box-wide
   thrum memory create --kind agent_rule --scope project \
     --title "<topic file name>" --oneline "<trigger>" \
     --full @"$SCRATCH/body.md" --tag claude-memory --tag indexed_in:runtime_memory --json
   ```

   Use `--kind lesson` for a habit or lesson rather than a rule.

4. Verify byte for byte before touching the index:

   ```bash
   thrum memory show <ID> --format body --zoom full > "$SCRATCH/back.md"
   cmp "$SCRATCH/body.md" "$SCRATCH/back.md"
   ```

   If they differ only by a trailing newline, that is acceptable; note it. Any
   other difference: stop and do not change that index line.

5. Add `thrum_memory: <ID>` to the topic file's frontmatter `metadata`.
6. Box-wide entry: replace that entry's text in MEMORY.md with the
   trigger-format line. Change only that one entry. Entries packed on one line
   with `·` are separate entries: move only the one you are converting and leave
   its neighbours as they are. Personal entry: add no index line, and leave the
   entry's existing line as it is, unless an index report names it.

### Fixing an index report

`thrum prime` can print a section at a fresh start that lists problems in your
runtime's shared index file. Fix them in that file:

| Runtime     | Index file                                                                                                                    |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Claude Code | `~/.claude/projects/<slug>/memory/MEMORY.md` (the report prints the path)                                                     |
| Muse        | `~/.local/share/muse/memory/personal/MEMORY.md`                                                                               |
| Codex       | `~/.codex/AGENTS.md`, or `AGENTS.md` in `$CODEX_HOME` when that is set to an absolute path (create it when it does not exist) |

Other agents on the machine share the file: read it again just before you edit,
change only the lines named, and match each finding by its ID, because the line
numbers move when another agent edits the file. To judge a finding, read the
memory with `thrum memory show <ID> --format body --zoom full`.

Nothing in an index is ever deleted. Removing an entry is a human decision, and
no finding below asks you to do it.

The Codex and Muse files are shared by every project on the machine, but a
project's memories live in that project's own store, so a line can point to a
memory that belongs to another project. Such a line reads `not found` here and
is not a mistake: leave it where it is.

| Finding                 | Meaning                                                                           | Do                                                                                                                                      |
| ----------------------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `WRONG line N`          | the line points to a memory that is superseded, purged, archived or unknown       | repoint it when the memory was superseded and its successor is clear; otherwise leave it and tell the owner (below)                     |
| `CHECK line N`          | the line's text differs from the memory's text (`memory says:`)                   | replace the text before `→` with the memory's text; keep the ID                                                                         |
| `MISSING <text> → <id>` | a box-wide memory has no line in this runtime's file                              | add the line ``- <text> → `<id>` `` to this file; the memory may already be in another runtime's index, and the same line fixes it here |
| `STRAY line N`          | the line holds an ID that the report could not read as a pointer                  | read the line; if it is meant as a pointer, rewrite it as ``- <trigger> → `<id>` ``, otherwise leave it                                 |
| `SIZE <path> is NN%`    | the file is over 75% of 32,768 bytes, the size the report treats as Codex's limit | shorten the longest lines, keeping every pointer; the line has no per-line fix                                                          |

An entry packed on one line with `·` is a separate entry: change only the one
the finding names.

For a `MISSING` line: the tag `indexed_in:runtime_memory` is box-wide, so each
runtime's report lists the memory until that runtime's own file has the line.
When you add a box-wide memory, add its line to every runtime index file you can
reach on this machine: the Claude file for this project, the Codex file and the
Muse file in the table above. Add only; never change another line there. Skip a
file you cannot find (except your own runtime's file, which the report says to
create) and say in your report which file you skipped. An entry you add to a
file that is not your runtime's is written by you, never by thrum. If an index
file is tracked in a repository (for example an AGENTS.md chain; check with
`git ls-files --error-unmatch <path>` run in its directory), edit it only where
this skill already tells you to edit that file, and leave any other tracked file
as it is. In your report, say which files you changed and which you left.

For a `WRONG` line:

- Superseded memory: find the memory that replaced it. `thrum memory show` does
  not render edges, so search for it with `thrum memory search` on the old
  memory's text. If exactly one active memory plainly replaces it, repoint the
  line: put the successor's ID after `→` and its text before it, written the way
  the old line was written. If you cannot tell which memory replaced it, treat
  the line as the next case.
- Purged, `not found`, or archived with no successor: you cannot repoint the
  line. Leave it in place and change nothing. The report keeps listing it at
  each fresh start. Tell the owner, who decides whether to remove it.

### Rules

- Never delete a topic file, a thrum memory or an index entry. This skill only
  adds records and shortens lines.
- Never merge two entries into one line or one record.
- Never reword the full text. It is copied exactly.
- Do not convert the FORMAT CONTRACT header or the hook warning at the top of
  MEMORY.md. They must stay in full in the index, because they guard against
  editing the index wrongly.
- thrum memories are local to this machine. Do not convert an entry another box
  has to read.
- After a batch, reload MEMORY.md and check its size is below 24.4KB, then
  re-read three converted entries' full text through the ID to confirm they come
  back.

### Using converted entries

When a trigger matches what you are about to do, read the full rule before
acting. The trigger is not the rule. The exact command, run from the thrum repo
(thrum finds its daemon from the current directory, and the memory folder is not
a repo):

```bash
cd <repo> && thrum memory show <ID> --format body --zoom full
```

If thrum is unreachable, find the topic file by its ID (grep above) and read it:
it holds the same text.

The index header carries this command once, near the top. Do not repeat it on
each index line; one copy at the top is always in view and costs a fraction of
the space.

### Other runtimes (survey 2026-10-21, agents' own reports, mostly not measured)

The pattern works on every runtime. What changes is where the index lives and
where the skill is installed. In every case, spell out the read command with
`cd <repo> &&`: no runtime resolves an ID by itself, and shells may be fresh
subshells.

| Runtime     | Where the trigger index goes (always loaded)        | Skill location                                    | Limits                                                                                                                                                    |
| ----------- | --------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code | `~/.claude/projects/<slug>/memory/MEMORY.md`        | `~/.claude/skills/`                               | 24.4KB index read limit                                                                                                                                   |
| Codex       | AGENTS.md chain                                     | `~/.agents/skills/`                               | ~32KiB `project_doc_max_bytes`; MEMORY.md not read                                                                                                        |
| OpenCode    | AGENTS.md / CLAUDE.md (loaded in full)              | `~/.config/opencode/skills/` or `.claude/skills/` | skill description always loaded: keep it short                                                                                                            |
| Muse        | its own MEMORY.md (native read_memory)              | already sees `~/.claude/skills/`                  | no cutoff at 40KB (measured 2026-10-21, 401 lines); higher untested. Prefers its own topic files; use thrum IDs only for rules shared with other runtimes |
| Cursor      | `.cursor/rules/<name>.mdc` with `alwaysApply: true` | `.cursor/skills/`                                 | always-apply text loads in full, so this saves the most                                                                                                   |
| Copilot     | AGENTS.md or the Copilot plugin                     | `~/.copilot/installed-plugins/`                   | ~41KB output cap on prime                                                                                                                                 |
| AGY         | AGENTS.md / GEMINI.md / `.agents/rules/`            | `.agents/skills/`                                 | 24KB per file, 20k-token rules budget; tool is `run_command`                                                                                              |

Each box needs its own installed copy in its runtime's skill location, and thrum
memory IDs are local to each box's daemon.

### Licensing

`thrum memory create` needs the memory.substrate entitlement. The helper checks
it through the daemon: a `thrum memory edit` on a probe ID returns "not found"
only when the entitlement is granted, because the gate runs before the lookup
and nothing is written. The check does not look at the license tier, so any tier
that the server grants the feature to proceeds. Without the entitlement the
helper prints "needs Thrum Pro (free for eligible public repositories)", exits
7, and changes nothing: no record and no index change.

### Improving this skill

If a trigger fails to stop a wrong action, or a step here is unclear, fix this
file in the same turn and note what changed.
