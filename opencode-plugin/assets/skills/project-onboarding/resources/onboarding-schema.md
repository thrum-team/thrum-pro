# onboarding.json and the policy contract

This is the contract between the onboarding skills. `.thrum/policy/onboarding.json` is the progress record; it is
committed with the code, so it holds only what is safe to commit. Every section skill writes its own entries and no
one else's. A key that a later section needs is never left out: a writer that skips its question writes the empty
value (`[]`, `false`) instead.

## Top-level keys

| Key | Holds | Written by |
|---|---|---|
| `sections` | one entry per section, `S1` to `S6` | each section skill, at its end |
| `answers` | answers that drive later sections | see "### answers keys" |
| `coupling` | `work_list`, `changed_scope_viable`, `source` | the coupling skill |
| `licence` | the licence record | the licence-read block |
| `variant` | the installed variant | `onboarding-coordinator` |
| `profile` | `solo` or `team` | `project-onboarding` |
| `reported` | notices already sent | skills and scripts |
| `answers_source` | how each answer was given, see "## Interview records" | each part, with its answers |
| `answers_notes` | the notes the owner added to rows, see "## Interview records" | each part, with its answers |

## `sections.<S>`

`sections.S1` to `sections.S6`, one per section: `{status, reason, date, sha}`.

- `status` is `done`, `skipped`, `partial` or `undone`. Undo marks a section `undone`, so the skills raise the
  missing-policy notice for it again.
- `reason` is `owner` (the owner chose to skip) or `profile` (the Solo profile skipped it). It is set when `status` is
  `skipped`.
- `date` is `YYYY-MM-DD`; `sha` is the commit the section ran against.

The keys map to skills: `S1` is `onboarding-security`, `S2` is `project-philosophy`, `S3` is `onboarding-coupling`,
`S4` is `onboarding-gates`, `S5` is `onboarding-checks`, `S6` is `onboarding-coordinator`.

## answers

### answers keys

Each key is `answers.<key>`, written by one or more sections and read by others (writer → reader).

- `answers.deployment_shape`, `answers.external_calls`: S1 → S2 prefill.
- `answers.security_depth`: S1 → S1.
- `answers.burn_down`: S2 → S4.
- `answers.ratchet_candidates`: S3, S4 → S4. S4 appends the found ratchets the owner brought in.
- `answers.inventory`: the umbrella (`pending` records), S1, S2, S4, S6 (`decision`, `copy`) → S1, S2, S4, S6.
- `answers.lane_scope`, `answers.topology`: S4 → gate-setup prefill and S6.
- `answers.hot_paths`: S4 → hotpath-gate prefill.
- `answers.cadence`: S5 → S6.
- `answers.reminder_cadence`: S6 → S6 (`1h` by default, or `off`).
- `answers.dashboard`: S6 → S6, and the umbrella's dependency rule. `true` when the dashboard is installed; `false`
  when it was not offered or was declined.
- `answers.rulings`: S1, S3, S4 → S6 (see "answers.rulings" below).

`answers.ratchet_candidates` and `answers.hot_paths` are lists. A writer that skips the question writes `[]`.

### answers.rulings

`[{id, date, trigger, rule, applies_to, from}]`.

- S1 appends each non-goal (`applies_to: all`). S3 appends each keep-separate rule the owner picked (`applies_to: all`).
  S4 appends each default the owner changed (`applies_to: coordinator`). S2 appends each rule brought in, and S6 each
  note brought in. S6 reads the list and writes the rulings out.
- `applies_to` is a role name or `all`.
- `from` for a ruling not made from an import is `<section title>, <policy file>[#<anchor>]`:
  S1 `<section title>, security-model.md#non-goals`,
  S3 `<section title>, coupling.md` and
  S4 `<section title>, gates.json`.
- `id` is `r-<n>`, the next number not yet used in `answers.rulings`. Ids are never reused.
- For a ruling made from an import, `trigger` is "working in this repository", `rule` is the item's first line,
  `applies_to` is `all`, and `from` is `<section title>, imported/rules.md#i-<n>`.

### answers.inventory

`[{path, position, hash, kind, offered_in, decision, copy}]`.

- `kind` is `rule`, `note`, `ratchet`, `gate-command`, `hook`, `skill` or `security-note`.
- `offered_in` is `S1`, `S2`, `S4` or `S6`.
- `decision` is `pending`, `bring-in`, `leave`, `prefilled` or `skipped-credential`.
- `copy` is the copy's entry id `i-<n>` without brackets (the heading `### [i-<n>]` is the only place brackets appear)
  or path, or absent.
- The copy entry header is `### [i-<n>] <YYYY-MM-DD> — from <path>:<line> — hash <12 hex> — ruling r-<n>`, followed by
  `— file imported/notes/<path>` when a file was copied with it. `i-<n>` is never reused.

## Interview records

Four keys record how the interview ran.

- `answers_source`: answer key → `chosen` (owner gave or changed it), `accepted` (took the recommendation), `unsure`.
  `unsure` means the owner did not know, and the recommendation was used.
  A key may name a row that has no answers key, such as `security_actor_<slug>`.
- `answers_notes`: answer key → the note the owner added to that row. A key with no note is absent.
  Each part's skill names its keys.
- `answers.interview_channel`: `terminal` or `dashboard`. Absent reads as `terminal`.
- `answers.unvalidated_commands`: a list of commands whose validation run the owner skipped; `[]` when none.

## coupling

- `coupling.work_list` is `tracker` or `coupling.md`. Written by S3.
- `coupling.changed_scope_viable` is a boolean. Written by S3, read by S4.
- A Solo run that skips S3 writes `coupling.changed_scope_viable: false` with `coupling.source: "solo-default"`. An owner
  skip writes `false` with `coupling.source: "owner-skip"`. So S4 never meets a missing key.

## licence

The record is `{checked, status, tier, capabilities[], repo_capabilities[], oss_grants}`, copied from
`thrum license status --json`.

Copied fields: `status`, `tier`, `capabilities`, `repo_capabilities`, `oss_grants`.
`checked` is the time the skill read the licence.

Never copied: `registration_record`, `machine_id`, `repo_origin`, `repo_id`. `registration_record` is never copied,
because it holds the machine and repository identifiers and `onboarding.json` is committed. Nothing else in the
command's output is copied either (`revoked`, `expires_at`, `plan_ends_at`, `machine_alloc`, `renewal_status`,
`revoked_message`).

```json onboarding-licence-example
{
  "checked": "2026-11-04T17:45:02Z",
  "status": "active",
  "tier": "paid",
  "capabilities": ["queue.write", "state.write", "memory.substrate", "dashboard.write"],
  "repo_capabilities": ["queue.write", "state.write", "memory.substrate", "dashboard.write"],
  "oss_grants": { "source": "cached_token", "state": "empty", "repos": [] }
}
```

- What the command prints on a Free install: `status` is `unlicensed`, `capabilities` is `[]`, and `tier` and
  `oss_grants` are absent. `status` can also be `active`, `expired` or `unreadable`. `tier` is `paid`, `comp`, `trial`
  or `enterprise` when present.
- `oss_grants` is the command's object `{source, state, repos[]}`, or absent. It is present only when the licence is
  active. `state` is `present` when a grant exists, and otherwise `empty`, `unsupported_schema` or `unreadable`. `repos[]`
  lists repositories as plain strings (canonical repository ids). `capabilities` ignores a repository grant, so a
  machine with only a repository grant shows `capabilities: []`.
- `repo_capabilities` is the licensable capabilities granted for this checkout's repository, computed by the licence
  gate's own query, so machine grants and this repository's grants both count. It holds capability names only and no
  repository id. An absent `repo_capabilities` contains nothing, so the variant is `free`.
- The licence-read block rewrites the record before the first question: at the start of every umbrella run, and
  whenever `onboarding-security` or `onboarding-coordinator` runs alone. If the command fails the record is
  `{checked, status: "unknown", capabilities: []}`, with no `tier` and no `oss_grants`.

### The variant rule

The derived variant is `pro` when `repo_capabilities` contains all three of `queue.write`, `state.write` and
`memory.substrate`. Otherwise it is `free`. The skill never matches `oss_grants.repos[]` itself
and never derives a repository id. The dashboard is offered only when the variant is `pro` and `repo_capabilities`
also contains `dashboard.write`.

`variant` is `{value: pro|free, date}`. It is written only by `onboarding-coordinator` when it installs, so it records
what is installed. `licence` describes the licence now and `variant` describes what is installed. A difference between
the derived variant and `variant` is a licence change.

## profile

`profile` is `solo` or `team`, written by `project-onboarding`. A section run alone leaves it unset and treats an unset
value as `team`.

## reported

`reported` is a list of signatures of notices already sent, written by skills and scripts. A skill or script checks it
before it sends a notice and sends a given signature only once. A signature names what the notice is about, so a
changed condition gets a new one. The shapes:

- missing policy: `missing:<file under .thrum/policy/>[:<key>]`, with the key only when a key is missing;
- skipped section: `skipped:<skill>:<reason>`, where `<reason>` is `owner` or `profile`;
- licence change: `licence-change:<recorded variant>-><derived variant>`;
- fixed: `imported-copies` (the notice that imported copies are committed) and `committed-files:<variant>` (the notice
  that the work list and rulings are committed).

```text onboarding-reported-examples
missing:gates.json:batch.every_n_landings
skipped:onboarding-coupling:profile
licence-change:free->pro
imported-copies
committed-files:free
```

## installed.md rows

Every section appends one row for each write it makes outside `.thrum/policy/` and `.thrum/results/`, and one for every
role block it writes. Each entry written into `.thrum/policy/imported/rules.md` also gets an `imported-from` row, which
also names a file copied with it.

The row is:

| id | kind | target | prior | schedule | script | section | status |
|---|---|---|---|---|---|---|---|

`id` is `inst-<n>`, the next number not yet used in `installed.md` (`inst-1`, `inst-2`, ...). Ids are never reused. Read
installed.md again before each row you add, and use one more than the highest inst- number in it, counting removed rows.

`section` is the name of the skill that wrote the row, for example `onboarding-security`, never a section label.

`status` is `active`, or `removed <YYYY-MM-DD>` after Undo. A re-run treats a `removed` row as absent and never adds a
duplicate of an `active` row.

The kinds are exact strings, and each kind fixes what `target` and `prior` hold and how Undo reverses it:

| kind | `target` | `prior` | Undo |
|---|---|---|---|
| `monitor` | the monitor id from `thrum monitor list` | — | remove the monitor |
| `kept-monitor` | the existing monitor's name | — | remove the row only; the monitor is the owner's and is never stopped |
| `role-block` | `<role>:<marker owner>` | — | remove the marked block (read, replace, write) |
| `state-scope` | `<kind>:<scope>` | — | on the owner's yes, after offering a copy to the Free file |
| `memory-rule` | the memory id | — | on the owner's yes, after offering a copy to `rulings.md` |
| `config-write` | the `thrum config` key, and for a map key its entry, as `orchestration.merge_kings[<target>]` | the entry's value before onboarding, or `absent` | read the whole value with `thrum config show <key> --json` (its `value`), restore the entry (or delete it when `prior` is `absent`), and write the whole value back with `thrum config set <key> '<JSON>'`; when the map would be empty, `thrum config unset <key>` |
| `agents-md-line` | `AGENTS.md` or `CLAUDE.md` | — | remove the marked block |
| `copied-item` | `<destination>:<id>` (queue, dashboard, memory or state) | — | on the owner's yes |
| `tracker-issue` | `<tracker>:<id>`, where `<tracker>` is `beads` or `native` | — | list only, shown with `bd show <id>` or `thrum issue show <id>`; never removed |
| `imported-from` | the entry imported/rules.md#i-<n>, plus " + imported/notes/<path>" when a file was copied with it | the source path:line at import (a duplicate lists both, separated by ", ") | list only; the copy is kept with .thrum/policy/ and the source is never touched |

## The result files for the Free setup

The interview's content files (security model, philosophy, coupling, gates, checks) are identical on both variants. The
coordinator's role block, the dash-tick prompt and the reminder text are written in the variant's form. The tracking
layer has a Free form of each Pro primitive:

| Pro (write-gated) | Free variant | Committed? | Writer → readers |
|---|---|---|---|
| `thrum queue` | `.thrum/policy/worklist.md`, section `## Work` | yes | S6, the coordinator → the coordinator, the hourly reminder |
| dashboard action-picks | `.thrum/policy/worklist.md`, section `## Owner questions` | yes | a section that continues with a gap recorded, the coordinator → the coordinator, who asks the owner by pane or message at each dash tick |
| `thrum memory` `agent_rule` | `.thrum/policy/rulings.md` | yes | S6, from `answers.rulings` → every role, through the security role pointer |
| `personal_state` and topic scopes | `.thrum/results/coordinator-state.md` | no (local) | the coordinator at each dash tick → the coordinator after a restart |

The coupling work list goes to the tracker on both tiers, with the `coupling.md` checklist as the fallback. Check
delivery is pane or inbox. Every run of a check also overwrites `.thrum/results/reports/<check>.md` with its latest
report.

- `worklist.md` item line: `- [ ] [w-<n>] <what> — from <section title or coordinator> — added <YYYY-MM-DD>`. When an
  item is done, the box is ticked and `— done <YYYY-MM-DD>` is appended. `w-<n>` is never reused.
- `rulings.md` line, one per ruling: `- [r-<n>] <YYYY-MM-DD> — when <trigger> — <the rule> — applies to <role|all> —
  from <section title>[, imported/rules.md#i-<n>]`. `r-<n>` is the `answers.rulings` id.
- Ids across variants. Converting between variants copies each item with its id. On Pro the id goes in the queue item's
  `--ref onboarding:<id>`, the memory body's first line, or the state value. An id that already exists at the
  destination is skipped, so converting twice, or back and forth, never duplicates anything.
- `coordinator-state.md` is rewritten whole by the coordinator at each tick. Headings, in order: `## Current state`,
  `## Next actions`, `## Merge gates`, `## Security`, `## Scope`. Each of the last three ends with a `Cold successor:`
  line, the Free form of the topic scopes' `cold_successor`.
- Location. `.thrum/results/` falls under `/.thrum/*`, which `thrum init` ignores, so the folder stays local without a
  new gitignore line. `.thrum/policy/` is committed, except in stealth mode, where all of `.thrum/` is local.
  `.thrum/policy/` is committed, so every checkout, worktrees included, reads its own copy at the checkout root.
  `.thrum/results/` is local and, from a worktree, is resolved through `.thrum/redirect`. In stealth mode a worktree
  has no `.thrum/policy/` copy; skills there resolve it through `.thrum/redirect`.

## Owned blocks

One format, used by every writer: `<!-- onboarding:<owner> -->` … `<!-- /onboarding:<owner> -->`. `<owner>` is the
writer: `S1`, `S3`, `S6` or `configure-roles`. A writer edits a file in one pass:

1. Read the file. For a role file, use `thrum roles rules show <role>`.
2. Replace only its own block, or append it if it is absent.
3. Write the file back. For a role file, use `thrum roles rules set <role>` with the whole content on stdin, then
   `thrum roles deploy`.

Writers run one after another within a section run, never at the same time.

## The watch list

One fenced block in `.thrum/policy/security-model.md`, written by S1 and read by the security check:

````markdown
```yaml onboarding-watch-list
non_goals_confirmed: true        # at least one owner-confirmed non-goal exists
watch:
  - pattern: "<extended regex>"  # matched against added lines
    why: "<the non-goal or watch item it guards>"
```
````

## Migration note

Before 1.1, these files lived at `.thrum/philosophy.md`, `.thrum/gate-config.json`, `.thrum/hotpath-gate.json` and `role-rules/`.
