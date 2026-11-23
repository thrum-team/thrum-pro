<!-- markdownlint-disable MD013 -->

# Inventory

The inventory finds what the owner already has in this repository, offers it in
the section it fits, and brings it in only on a yes. The umbrella skill runs it
once, before the first section question. It only reads, and it writes only
`answers.inventory`. The section that offers an item writes the copy, the lane
or the entry, after the owner says yes. "Leave" writes nothing for any kind.

## What is found, and which section offers it

Worded generically; the tools named are examples.

| Found                                                                                                                                                                                                                    | `kind`          | `offered_in` | Bring in does                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------- | ------------ | ------------------------------------------------------------------------------------------------ |
| rules in `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `CONVENTIONS.md`                                                                                                                                                      | `rule`          | `S2`         | copies the item into `imported/rules.md`; it becomes an owner ruling                             |
| notes and memory entries: `MEMORY.md`, `memory/`, `notes/`, `docs/adr/`, decision logs                                                                                                                                   | `note`          | `S6`         | as for a rule; a linked or whole-file note's file goes to `imported/notes/<path>`                |
| ratchet scripts and targets, paired with a ceiling file (see Ratchet pairing)                                                                                                                                            | `ratchet`       | `S4`         | a `ratchets[]` entry that runs the owner's script against the owner's ceiling; nothing is copied |
| the commands the gates section detects: CI `run:` steps, `Makefile`/`justfile` targets, `package.json` scripts                                                                                                           | `gate-command`  | `S4`         | a lane that calls the owner's command; nothing is copied                                         |
| git hooks: `.pre-commit-config.yaml`, `.husky/`, the `core.hooksPath` directory                                                                                                                                          | `hook`          | `S4`         | a lane (see Hooks as lanes)                                                                      |
| custom skills, commands and agent prompts: `.claude/skills/`, `.claude/commands/`, `.claude/agents/`, `.agents/skills/`, `.codex/skills/`, `.cursor/skills/`, `.opencode/skill/`, `.opencode/skills/`, `.github/skills/` | `skill`         | `S6`         | a line naming its path inside the coordinator's role block; no copy and no row of its own        |
| security notes: `SECURITY.md`, threat-model docs                                                                                                                                                                         | `security-note` | `S1`         | prefills the security scan report and non-goals question; recorded `prefilled`, no question      |

A skill folder that holds a file named .thrum-role-bundle.json was installed by
a role bundle, not by the owner: do not list it.

## Reading first, writing only on a yes

Show the reading line before anything is read. It informs and asks nothing,
because reading changes nothing.

> Say: Before asking anything, I will read the files in this repository that
> look like rules, notes, ratchets, gates, hooks, custom skills and security
> notes. I only read them now. Anything you choose to bring in later is copied
> into .thrum/policy/imported/ or used where it is; bringing something in never
> changes the original.

Only files inside the repository are read. A runtime's memory folder outside the
repository is not.

After reading, and before the first question, list every file that was read, by
path, with its item count. A file that was read and has no offered item, such as
an `AGENTS.md` that holds only Thrum's own blocks, is listed with 0 items. An
item skipped because it matches a credential pattern is listed as skipped.

A rules file with no list items is listed with 0 items and gets this line:

> Say: <path> has its rules written as paragraphs. I only pick up list items, so
> nothing from it is offered. Turn a paragraph into a list item to have it
> offered.

## What counts as one item

- In a rules file: one top-level list item, meaning a line starting `-`, `*` or
  `<n>.` followed by a space, at column 0, together with its indented
  continuation lines. Prose paragraphs, headings and code blocks are not
  offered. Neither is text inside a block that Thrum writes:
  - an `<!-- onboarding:... -->` block;
  - the block from a line starting `<!-- BEGIN THRUM TRACKER` to
    `<!-- END THRUM TRACKER -->` that `thrum init` writes, in any version;
  - the block from a line starting `<!-- BEGIN THRUM SAFETY RULES` to
    `<!-- END THRUM SAFETY RULES -->` that runtime init writes.

  The `@AGENTS.md` import line that `thrum init` adds to `CLAUDE.md` is not
  offered either.

- In `MEMORY.md`: one top-level list item. If it links to a file inside the
  repository, that file goes with it: it is part of that item, is not offered as
  an item of its own, and has no record of its own.
- In `memory/`, `notes/`, `docs/adr/` or a decision-log folder: one file, unless
  a `MEMORY.md` item links to it.
- An item's position is its ordinal among the top-level items of its file.

## Duplicates

Two items are the same when their text matches after lowercasing, collapsing
whitespace, and removing the list marker and trailing punctuation.

- A duplicate pair is offered once, naming both sources, by the earlier of the
  two sections in S1 to S6 order.
- Bringing the pair in makes one copy entry, which lists both sources, and one
  ruling.
- The other source's record gets the same decision and `copy`, so the later
  section does not offer it.

## Ratchet pairing

A ratchet candidate is either:

- a script or `Makefile`/`justfile` target whose name contains `ratchet`,
  `baseline`, `ceiling` or `budget`; or
- a script that reads a checked-in file whose name contains one of those words.

The ceiling is the file the script reads. If no read can be found in the script
text, the pairing is a guess:

- `<file>` is the checked-in data file (not a script, a `Makefile` or a
  `justfile`) whose name contains one of the four words and that is nearest the
  script: the script's own directory first, then the repository root. A file
  that another script already reads is not a guess. Two equally near files are
  each their own row.
- Team makes the ceiling one row of the inventory block, asking in plain words
  whether `<file>` is the ceiling that `<script>` checks against. On "no" to
  every guess, the script is offered as a gate command instead.
- Solo does not ask the pairing question. A guessed pairing is offered as a gate
  command in the gates table question.
- With no such file, nothing is asked, and the script is offered as a gate
  command.

## Hooks as lanes

- A `.pre-commit-config.yaml` hook becomes `pre-commit run <id> --all-files`.
- A file in `.husky/`, or in the `core.hooksPath` directory, becomes that file's
  path, run with no arguments.
- A hook whose text reads staged changes (`git diff --cached`, `lint-staged`) is
  offered with this note:

  > Say: This hook checks only staged changes, so as a lane it may check
  > nothing.

## Credentials

- The scan covers every item, and every file that would be copied with an item.
- An item or file that looks like a credential is never offered, and the
  inventory prints its path and line as skipped. The patterns are a PEM
  `-----BEGIN` line, and the case-insensitive regular expression
  `(api_?key|token|secret|password)[[:space:]]*[:=][[:space:]]*[^[:space:]]+`.
- The patterns can also match harmless prose, such as "Token: 4k per call". That
  costs only a skipped offer and a printed line, never a write. Prose without
  `:` or `=` after the word, such as "token budget is 4k", is offered.

## The `reported` signature

`imported-copies` is the signature of the committed-copies line in the inventory
offer block. An offering section shows that line before its first copy, unless
`reported` already holds the signature, and then adds it.

## The record

`answers.inventory[]` holds
`{path, position, hash, kind, offered_in, decision, copy}`.

- `kind` is `rule` | `note` | `ratchet` | `gate-command` | `hook` | `skill` |
  `security-note`.
- `offered_in` is `S1` | `S2` | `S4` | `S6`.
- `decision` is one of:
  - `pending`, written for each item found that has no record yet (matched by
    the re-run rules below). The inventory never changes an existing record;
  - `bring-in` or `leave`, set by the offering section;
  - `prefilled`, set by the security section for a security note;
  - `skipped-credential`, written in place of `pending` for an item the
    credential patterns match.
- `copy` is the copy's entry id `i-<n>` without brackets (the heading
  `### [i-<n>]` is the only place brackets appear) or path, or absent.

## The copy layout

- `.thrum/policy/imported/rules.md`: one entry per rule or note brought in,
  including a whole-file note and an item with a linked file, headed
  `### [i-<n>] <YYYY-MM-DD> — from <path>:<line>[, <path>:<line>] — hash <12 hex> — ruling r-<n>[ — file imported/notes/<path>]`.
  `i-<n>` is never reused.
- `.thrum/policy/imported/notes/<repository path>`: the file of a linked or
  whole-file note, byte-identical; the entry header names it.
- Each entry gets one `installed.md` row of the kind `imported-from`. Its
  `target` is the entry, `imported/rules.md#i-<n>`, followed by a space and
  `+ imported/notes/<path>` when a file was copied with it, and `prior` is the
  source `path:line` at import (a duplicate lists both, separated by a comma and
  a space). Undo lists these rows and never removes a copy or touches a source
  (`.thrum/policy/` is kept unless the owner says to delete it).

## Re-runs

- Each decision is remembered in `answers.inventory`. An item is matched by
  source path and text hash first. For a ratchet the hash covers the script
  only: a changed ceiling is not a changed item, because the owner's script
  reads its ceiling when it runs.
- An item already brought in or left is not offered again.
- An unmatched item at the same path and position as a recorded one is
  "changed". Show the copy next to the new text and ask whether to refresh. On a
  yes, write a new copy entry `i-<m>`, mark the old entry's header
  `— replaced by i-<m>`, append a new ruling, and offer to remove the old
  ruling. That removal uses the same yes-gate as Undo.
- A recorded item that is no longer in its source is reported. Its copy stays.
- Any other unmatched item is new, and is offered.
- Undo is the one way a `bring-in` record returns to `pending`: when the owner
  removes a ruling made from an import. Bringing it in again with an unchanged
  text hash reuses its entry `i-<n>` and writes only a new ruling.

## Free and Pro

The copies are identical on both variants. Rulings made from them follow the
variant: on Free, `rulings.md`; on Pro, `agent_rule` memories. The coordinator
section writes both from `answers.rulings`.
