---
name: project-philosophy
description: "Use when a project needs its implementation philosophy established or updated — the canonical doc at .thrum/policy/philosophy.md defining anti-patterns, red flags, and project-specific rules that implementation agents read at task-start time. First invocation generates from project inspection; subsequent invocations reconcile against current project state and propose diffs."
---
<!-- markdownlint-disable MD013 -->

# Project Philosophy

## Missing policy files

This skill writes `.thrum/policy/philosophy.md`. When that file is absent the skill is in first-run mode, which is not a
miss. It reads `.thrum/policy/security-model.md` in Step 6a, and a missing security model does not stop it.

<!-- onboarding:alert -->
**Missing policy.** Do this before you read a policy file, and again whenever a step needs a key from one.

1. Check that the file exists and has the key you need. A file that exists but lacks the key is a miss. A file whose
   writing section `.thrum/policy/onboarding.json` records as `undone` is a miss although the file is kept.
2. On a miss, when the owner is present, first say this, with `<part>` the part that writes the file, in plain words:

   <!-- markdownlint-disable MD013 -->
   > Say: I can't do this step yet: <file> is missing because the <part> has not been set up. Run <skill> to add it.
   <!-- markdownlint-enable MD013 -->

   Then print `ONBOARDING MISSING: .thrum/policy/<file> [key <k>] (written by <skill>); run <skill>`. `<skill>` is
   the name of the skill that writes the file (for example `onboarding-gates`), never a section label. Leave out
   `[key <k>]` when the whole file is missing.
3. Message the coordinator with that line, unless you are the coordinator.
4. Stop the step that needs the file. Never continue with defaults.
   Never take the value from another record instead: `onboarding.json`'s `answers`, an earlier verdict, or what you
   remember of the file. Those record what was decided; only the file is the setting.
5. If `.thrum/policy/onboarding.json` records the section that writes the file as `skipped`, word the notice by its
   `reason`. It still stops:
   - `owner`: `ONBOARDING MISSING: .thrum/policy/<file> [key <k>] (owner-declined); run <skill> to add it`
   - `profile`: `ONBOARDING MISSING: .thrum/policy/<file> [key <k>] (skipped for the Solo profile; run <skill> to add it)`

   A section recorded `undone` gets the plain wording from step 2.
6. Check `reported` in `.thrum/policy/onboarding.json` first, and send a given signature once: `missing:<file>` or
   `missing:<file>:<k>`, or `skipped:<skill>:<reason>` when step 5 applies. After you send it, add it to `reported`. If
   `onboarding.json` does not exist, treat `reported` as empty and no section as skipped.
<!-- /onboarding:alert -->

<!-- markdownlint-disable MD013 -->

## Opening offer

Show this offer before any other question.

<!-- onboarding:offer -->
> Say: This part writes your engineering rules: the habits every agent should follow and the mistakes it should refuse to make. It asks a few questions about how you like code written, and offers rules you already keep in files such as CLAUDE.md.
> Ask: Do this part now, or skip it for now? If you skip it, running project-onboarding again offers it again.
<!-- /onboarding:offer -->

"Skip it for now" records `sections.S2.status: skipped` with `reason: owner` in `.thrum/policy/onboarding.json` and ends
the section. "Do it now" goes on. When this skill runs alone the same offer is shown, and a skip never changes a record
that is already `done`.

## History analysis

When .thrum/results/history-analysis.md is absent or stale, follow
history-analysis.md in the project-onboarding resources before the first block.

## Canonical path

`.thrum/policy/philosophy.md` — the single authoritative location. `project-setup` and
every implementation-agent prompt read from this path only. Non-standard paths
are handled by the fallback migration (documented below), not by moving the
canonical target.

## Run modes and dispatch order

On every invocation, dispatch in this order. Earlier branches short-circuit
later ones.

0. **Fallback migration** — runs first when `.thrum/policy/philosophy.md` is absent. If
   a legacy philosophy doc exists elsewhere in the repo, offer move/link/fresh
   before generating anything new. If no legacy doc is found, fall through to
   branch 1.
1. **First-run** (doc absent, no legacy doc or "fresh" chosen above) — generate
   a new `.thrum/policy/philosophy.md` from project inspection + interactive prompts
   (documented below).
2. **Re-run-unchanged** (doc present, matches current project state) — report
   "philosophy.md is current; no changes needed" and exit without writing.
3. **Re-run-evolved** (doc present, project has drifted) — compute a sectional
   diff, ask as a block following `resources/question-blocks.md` of project-onboarding, write only on confirmation.

Load the /thrum:generator-idempotency-protocol skill and follow it.

> **Note: human-in-the-loop required.** This skill asks as blocks, following `resources/question-blocks.md` of
> project-onboarding, for first-run project-specific prompts, re-run-evolved diff approval, and the
> fallback-migration three-way choice. It cannot run unattended in CI or any
> other non-interactive automation context. Invoke it only from a session that
> can answer prompts.

## Fallback migration

Runs before the First-run branch when `.thrum/policy/philosophy.md` is absent. If the
user has a philosophy doc at a legacy path, offer a three-way choice rather than
ignoring it and generating a parallel doc.

### Step 1: Search for legacy philosophy docs

```bash
find . -type f \( -name "*philosophy*" -o -name "*anti-pattern*" -o -name "*implementation-standards*" \) \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  2>/dev/null | head
```

Common legacy locations: `dev-docs/implementation-philosophy.md` and
`docs/anti-patterns.md`.

Then read CONTRIBUTING.md at the repository root, if there is one: the find above does not match it. If it has a heading
that names anti-patterns, it is a candidate: offer to link it or to start fresh.
Never offer to move it.

If zero candidates: fall through to First-run. If one or more candidates:
present the choice.

### Step 2: Present three-way choice as a block

Ask it as a block following `resources/question-blocks.md` of project-onboarding, with the choices Move / Link / Fresh
(pick one).

Question: "Found existing philosophy doc at `<path>`. What should I do?"

Options:

- **Move** — `git mv <path> .thrum/policy/philosophy.md`. Preserves history via rename;
  the file moves to the canonical location and the legacy path stops existing.
- **Link** — Create `.thrum/policy/philosophy.md` with a single line: `See: <path>`.
  The legacy doc stays in place; the canonical path becomes a pointer. Useful
  when the legacy path is load-bearing (e.g., referenced from another
  file that can't be retargeted cheaply).
- **Fresh** — Ignore the legacy doc; generate a new `.thrum/policy/philosophy.md` via
  the First-run flow. The legacy doc stays unmodified. Useful when the legacy
  doc is stale or incomplete.

The block is one row. Take `Recommended:` from the guidance above, applied to what was found: Link when the legacy path
is load-bearing (another file points at it), Fresh when the legacy doc is stale or incomplete. When that guidance does
not decide the case, `Recommended: Link`, and `Why:` says so, because Link changes least.

```text
Block 1 of 1: Existing philosophy document

1. Found existing philosophy doc at <path>. What should I do?
   Choices: Move / Link / Fresh (pick one)
   Recommended: Link
   Why: three other files point at it

Reply "yes to all", tell me what to change (for example "1: Fresh"), say "not sure about 1", or ask "explain 1".
```

Record how each answer was given in answers_source, and a note the owner added in answers_notes, under these keys, in
row order: philosophy_existing_doc.

When the candidate is CONTRIBUTING.md, the choices are Link / Fresh only. Leave Move out of the row.

If multiple candidates were found, ask which one first (a separate block) before offering move/link/fresh.

### Step 3: Execute the chosen option

**Move path:**

```bash
mkdir -p .thrum/
git mv <legacy-path> .thrum/policy/philosophy.md
```

`git mv` requires the repo to be initialized with at least one commit on the
current branch. If the repo has no commits (fresh `git init`), fall back to a
plain `mv` + `git add`, and note in the final message that rename history is not
preserved.

**Link path:**

```bash
mkdir -p .thrum/
printf 'See: %s\n' "<legacy-path>" > .thrum/policy/philosophy.md
```

**Fresh path:** Drop into First-run mode without touching the legacy file.

### Step 4: Announce and continue

Tell the user what was done and where the canonical doc now lives. If `move` or
`link` was chosen, exit (the doc is materialized — no further generation
needed). If `fresh` was chosen, continue into First-run Step 1.

## First-run mode

Triggered when `.thrum/policy/philosophy.md` does not exist AND no non-standard
philosophy doc is found (or the fallback migration is skipped via the "fresh"
option).

### Step 1: Detect language

Inspect the repo root for manifest files and pick the primary language:

| File present                                         | Language                |
| ---------------------------------------------------- | ----------------------- |
| `go.mod`                                             | Go                      |
| `package.json`                                       | JavaScript / TypeScript |
| `Cargo.toml`                                         | Rust                    |
| `pyproject.toml` or `setup.py` or `requirements.txt` | Python                  |
| `pom.xml` or `build.gradle*`                         | Java / Kotlin           |
| `Gemfile`                                            | Ruby                    |
| `mix.exs`                                            | Elixir                  |

If multiple are present, record the repo as polyglot and pick the most prominent
by file count.

### Step 2: Detect framework

Grep the detected language's manifest for well-known framework markers:

- Go: `cmd/` layout + `net/http` or `gin-gonic` or `chi` → web service; `cobra`
  → CLI; pure library if neither
- JS/TS: `next` in `package.json` → Next.js; `react` without Next → React SPA;
  `express`/`fastify` → Node backend
- Python: `fastapi`/`flask`/`django` in dependencies → web backend;
  `pytorch`/`tensorflow` → ML
- Rust: `tokio`/`actix-web`/`axum` → async service; bin-only → CLI

### Step 3: Detect test harness

Check for test files and harness config:

- Go: `*_test.go` files; `testing` package import → stdlib; `testify` →
  assertions; `ginkgo` → BDD
- JS/TS: `__tests__/` or `*.test.ts`; `jest.config.*`, `vitest.config.*`,
  `playwright.config.*`
- Python: `tests/` dir; `pytest.ini`, `conftest.py`
- Rust: `#[cfg(test)]` blocks; `cargo test` always available

Record the harness in the rendered template so implementation-agent prompts know
how to run tests.

### Step 4: Detect pattern conventions visible in existing code

Sample the codebase for:

- Error handling shape (Go: `if err != nil { return ..., fmt.Errorf(...) }`;
  Rust: `?` propagation; TS: try/catch vs. Result types)
- Logging convention (structured vs. `fmt.Println`; named logger vs.
  package-level)
- Public API shape (exported types, interface-heavy vs. struct-heavy)

Grep narrow — 20–50 lines is enough to surface the dominant convention. Don't
read the whole repo; surface what's consistent, let the user correct via
prompts.

### Step 4a: Probe for generalizable reliability classes

Read `resources/reliability-class-library.md`. For every class in it, run
the per-language probe matching the language detected in Step 1 (fall back to
the class's generic probe if the detected language has no dedicated entry).
If the owner skipped the history read, say in the probe's prompt that it must read no commit.
Record every hit as an adapted finding: the class name, the specific file/line
found, and a BAD/GOOD pair phrased in the target repo's own language and
idioms — never reuse the library's own example snippets verbatim, they are
illustrations of the SHAPE to look for, not text to paste.

A class with zero hits is not an error — record it as walked-and-not-found and
move on. This step runs before the interactive prompts (Step 5) so seeded
findings can be shown to the user as defaults they can accept, edit, or
decline, rather than starting from a blank prompt.

### Step 5: Interactive prompts for project-specific rules

Read `answers` in `.thrum/policy/onboarding.json` first and ask only the questions that are still open. A question
whose answer is already recorded there is not asked again; an answer from an earlier section (for example
`answers.deployment_shape`) prefills its question.

Ask the items the codebase can't reveal as ONE block, following `resources/question-blocks.md` of project-onboarding
(rows numbered, at most seven; a free-text row has no `Choices:` line; each row has `Recommended:` and `Why:`; end with
the reply line):

```text
Block 1 of 1: Rules for your repository

1. Which mistakes have you seen in this repository that agents should never repeat (with links to post-mortems if any)?
   Recommended: <the rule from the history analysis, or none added>
   Why: <short sha and subject of each supporting commit>
2. Which anti-patterns are you actively burning down?
   Recommended: none added
   Why: <one line naming the evidence, or the fallback line>
3. Which red flags are non-negotiable (for example "never rm -rf a session dir")?
   Recommended: none added
   Why: <one line naming the evidence, or the fallback line>
4. Which deploy or release constraints apply (for example "no pushes to main from agents")?
   Recommended: none added
   Why: <one line naming the evidence, or the fallback line>
5. Which external dependencies need care (for example "never call prod Salesforce APIs from tests")?
   Recommended: none added
   Why: <one line naming the evidence, or the fallback line>

Reply "yes to all", tell me what to change (for example "2: legacy handlers"), say "not sure about 3", or ask "explain 3".
```

Record how each answer was given in answers_source, and a note the owner added in answers_notes, under these keys, in
row order: philosophy_mistakes, philosophy_burn_down, philosophy_red_flags, philosophy_release, philosophy_dependencies.

Write the answer to the burn-down row to `answers.burn_down`. A row the repository gives no evidence for takes the
fallback line from `resources/question-blocks.md` and recommends `none added`, the fallback value for engineering rules
in `resources/profiles.md` under "Fallbacks". Never invent a recommendation for these rows.

When no row has evidence, say the fallback line once under the block heading, leave out the Why: lines, and
put the History: line under it.

When the history read was skipped or found nothing,
put the History: line under every fallback line, as question-blocks.md says.

Seed this block with the repeated-fix patterns from the history analysis. Each repeated-fix finding is its own row in
place of row 1, with `Recommended: add a rule` and a `Why:` line that names the supporting commits (short sha and
subject). With no finding, the mistakes row is a single row with the fallback line from `resources/question-blocks.md`.

A block holds at most seven rows. The count includes the inventory rows offered through the block. When the findings plus
the other rows would pass seven, split into "Block 1 of 2" and "Block 2 of 2", with the finding rows first. Head
each block `Block <i> of <k>`; with no split it is the `Block 1 of 1` heading above. The Move / Link / Fresh choice and the re-run Apply all / Select / Decline
choice are one-row blocks.

Philosophy doc quality comes from real answers, not filler.

Rules the owner already keeps in files such as `CLAUDE.md` or `AGENTS.md` are offered through this block, used here
for the `rule` records in `answers.inventory`:

<!-- onboarding:inventory -->
**Bring in what you already have.** Offer the items the inventory found for this section, never an item it skipped.

1. Offer each `answers.inventory` record whose `offered_in` is this section and whose `decision` is `pending`. With no
   `answers.inventory`, offer nothing. A `security-note` record is not offered: the security section reads it into the
   scan report and sets it `prefilled`.
2. Before the first copy is written, show the committed-copies line, unless `reported` already holds the signature
   `imported-copies`. After showing it, add that signature to `reported`.

   > Say: What you bring in is copied into .thrum/policy/imported/, which is committed with your code.

   In stealth mode, leave out the words about being committed with your code from every notice.

3. Team offers the part's found items as blocks in the form of `resources/question-blocks.md`, one row per item, or one
   row per file when the file has more than seven found items. A file with more than seven found items is one row. On
   that row, "choose one by one" opens its own blocks. Each row has the choices bring in / leave, `Recommended:` is
   `bring in`, and `Why:` says in one line what the item is.
   When you cannot say what an item is, recommend "leave" and use the fallback line.
   `<n>` on a file row never counts an item skipped as a credential.

   Solo asks one table question per section that has found items, covering all of them, and asks nothing when nothing
   was found. On that question, "choose one by one" opens blocks:

   > Ask: I found <n> things you already have that fit this part of the setup. Bring them all in, choose one by one, or leave them all?

4. When a ratchet script has only a guessed ceiling file, Team makes the ceiling a row of the block, in the same row
   form: the question is whether `<file>` is the ceiling that `<script>` checks against, the choices are yes / no,
   `Recommended:` is `yes`, and `Why:` names the file as the nearest checked-in data file to the script.

5. A ruling made from a brought-in item has these fields:
   - `trigger` is "working in this repository".
   - `rule` is the item's first line, without its list marker. For a whole-file note, it is the file's first heading,
     or failing that its first line.
   - `applies_to` is `all`.
   - `from` is `<section title>, imported/rules.md#i-<n>`, and the `rulings.md` line renders it as written. The full
     text stays in the copy.
6. After the copies are written, a section that wrote at least one copy shows this line once, as the last action of the
   copy step: the copy step is not finished until the line below is shown. A section that copied nothing does not show
   it, and a ratchet brought in is not a copy, so it does not count.

   > Say: Thrum's copy in .thrum/policy/imported/ is now the one to edit. Your original is untouched and is still read by any tool that reads it today, so a rule you change in one place should be changed in the other. A full re-run notices a changed original and offers to refresh the copy.
<!-- /onboarding:inventory -->

Each rule brought in is copied to `.thrum/policy/imported/rules.md`, gets an `imported-from` row in
`.thrum/policy/installed.md`, and is appended to `answers.rulings`. The coordinator section writes the ruling out.

### Step 6: Render the template

Read `resources/philosophy-template.md`. It is not token-substituted — it
uses bracketed prose placeholders (e.g. `[Criterion 1 — e.g., ...]`) that you
replace with real content, and `<!-- TODO: ... -->` comments for anything left
undetected or unprovided. Fill in:

- The intro/language/framework/test-harness lines from Step 1–3.
- The `## Anti-Patterns` section's `### 1.`–`### 3.` entries are universal
  defaults — leave them as-is unless a detected convention (Step 4)
  contradicts one.
- `### 4.` onward: one numbered section per Step 4a finding (an adapted class
  hit), in the order the classes are listed in the library, using that
  finding's BAD/GOOD pair and Why. If Step 4a found more than 2 classes, add
  as many numbered sections as the probe finds — the template's `### 4.`/
  `### 5.` are illustrative slots, not a fixed count. If Step 4a found fewer
  than 2, leave the remaining slot(s) as the template's own
  `[Project-specific anti-pattern]` placeholder rather than fabricating a
  finding.
- Any remaining `[...]` placeholder with no detected or provided value stays
  as a `<!-- TODO: … -->` line rather than silent emptiness.

### Step 6a: MANDATORY — wire the project's security model into the Decision Framework

Read `.thrum/policy/security-model.md`. It is written by `onboarding-security`. When it is missing because the security
part was skipped or not yet run:

Write the rules file without the security row, and add an owner question that names the security part.
Do not stop.

The question is not asked live. Add it to the rendered rules file as a TODO line (Step 6 keeps anything unprovided as a
TODO comment): `<!-- TODO: Run the security part: <what it adds> -->`.

For this one file this step overrides the stop in the missing-policy block: show no alert for security-model.md and carry on; every other missing policy file still follows the block.
This covers a file that is missing because the security part was skipped, recorded undone, or not yet run.

When the file exists but lacks the deployment shape, it is not missing: follow the missing-policy block at the top of this skill and stop
this step. Never continue with a default frame in that case.

Unless the file is missing (see above), the rendered philosophy MUST carry a Decision Framework row pointing at that
file — and that row MUST NOT be keyed on the word "attacker".

```text
| Does this add a GUARD, RETENTION RULE, PERMANENCE/IMMUTABILITY claim,
  AUDIT/FORENSIC requirement, TAMPER-EVIDENCE, or AUTHORIZATION/RECIPIENT
  check — WHETHER OR NOT it names an attacker? | Read the non-goals in
  .thrum/policy/security-model.md BEFORE designing it. It states the project's
  actual deployment shape. |
```

**A control whose key excludes its own target population is decoration** —
key the Decision Framework row on effect (adds a guard, retention rule,
permanence claim, audit/forensic requirement, tamper-evidence, or
authorization check), never on whether it names an attacker. Security-shaped
requirements often arrive wearing non-security vocabulary: durability,
forensics, compliance, "defence in depth", "must never be lost".

Carry the deployment shape from the security model into the row's text as the owner stated it, positively, not just
the exclusions. A reader who knows only what is out of scope will still import the wrong frame.

### Step 7: Write `.thrum/policy/philosophy.md`

Before the first write, show the rendered draft and this line:

> Say: Here is the draft of your engineering rules. I write it to .thrum/policy/philosophy.md when you say yes.

`mkdir -p .thrum/policy/philosophy` then write the rendered content to `.thrum/policy/philosophy.md` only after the owner
says yes; supporting files go under `.thrum/policy/philosophy/`. On a re-run, preserve the block between `<!-- onboarding:S3 -->` and
`<!-- /onboarding:S3 -->` exactly: `onboarding-coupling` owns it, and this skill never edits or removes it. Announce the
path in the final message so the user knows where to edit it manually later.

Then write `sections.S2` in `.thrum/policy/onboarding.json` (`status: done`, with the date).

## Re-run-unchanged mode

Triggered when `.thrum/policy/philosophy.md` exists. The goal is a fast,
side-effect-free sanity check that confirms the doc is still accurate for the
current project state.

### Step 1: Read the existing doc

Read `.thrum/policy/philosophy.md` in full. Parse its sections — at minimum the
language/framework line, the test harness line, and the anti-patterns list.

### Step 2: Sanity-check against current project state

Walk the same detection steps as first-run, but compare rather than write:

- Language / framework / test harness — do the current manifest files agree with
  what the doc claims?
- Anti-patterns in `CLAUDE.md` (or equivalent) — is every anti-pattern in
  CLAUDE.md reflected in the doc?
- Linters or test configs recently added — are they acknowledged?

Each check is a boolean "matches" vs. "differs". Keep the comparison narrow;
this mode should not do deep inspection.

### Step 3: If nothing differs — no-op exit

Print:

> `.thrum/policy/philosophy.md` is current; no changes needed.

Do NOT write to the file. Do NOT update mtime. Do NOT create backups. Exit
cleanly.

### Step 4: If anything differs — hand off to evolved mode

If at least one check reports "differs", transition to the re-run-evolved flow
(below). The drift detection from Step 2 becomes the input to the diff proposal.

Idempotency invariant: re-running `/project-philosophy` on an unchanged project
must never modify any file. Tests for this mode should confirm mtime is
untouched — `stat -c %Y .thrum/policy/philosophy.md` on Linux,
`stat -f %m .thrum/policy/philosophy.md` on macOS.

## Re-run-evolved mode

Triggered when `.thrum/policy/philosophy.md` exists AND the unchanged-mode sanity check
flagged drift. This is the load-bearing idempotency path — philosophy docs
accumulate learned anti-patterns over time, so silent overwrites destroy
context. The merge-proposal shape is the only correct shape.

> **Never silently overwrite.** Philosophy docs are not regenerated — they are
> evolved. If the user has added hand-written anti-patterns, post-mortem
> references, or team-specific notes, those must survive every re-run. A write
> without explicit user confirmation is a bug.

### Step 1: Read the existing doc

Same as re-run-unchanged Step 1. Keep the parsed sections in memory so the diff
proposal can cite them.

### Step 2: Detect drift

Four drift categories, conservative on purpose:

- **Language/framework version change.** `go.mod`'s `go 1.X` differs from the
  doc's stated version; `package.json` lists `next@15.x` but doc says
  `next@14.x`.
- **New test patterns in codebase.** `ginkgo` imports appear but the doc lists
  only `stdlib testing`. New `playwright.config.ts` exists but doc doesn't
  mention E2E.
- **New anti-patterns recorded in CLAUDE.md since last run.** Compare
  anti-pattern bullets in CLAUDE.md against the doc's `{{ANTI_PATTERNS}}`
  section; anything new in CLAUDE.md is a drift candidate.
- **New linters or code-quality tooling added.** `.golangci.yml`,
  `eslint.config.js`, `ruff.toml` that weren't mentioned in the doc.

Start conservative. Expand the detector list only based on real-use feedback —
over-eager drift detection pesters users and erodes trust in the skill.

### Step 3: Compute a proposed diff (sectional)

First omit any drift item already recorded in `.thrum/policy/philosophy-skipped.jsonl`, so a declined item is not
proposed again; with no such log, omit nothing.

Present drift as a readable sectional diff, one item per drift category. Each
item should have:

- The detected change in plain language
- A proposed edit (insertion / replacement / addition at the bottom of a
  section)
- A one-line rationale

Example shape:

```markdown
### Proposed updates to `.thrum/policy/philosophy.md`

**1. Framework version bump**

- Current: "Next.js 14"
- Proposed: "Next.js 15"
- Rationale: `package.json` lists `"next": "^15.0.0"`

**2. New anti-pattern from CLAUDE.md**

- Proposed addition under "## Anti-patterns":
  > - Never run migrations from an agent session — always via the release
  >   pipeline.
- Rationale: Added to CLAUDE.md in commit abc1234 after the 2026-03 incident.
```

### Step 4: Present as a block

Ask it as a block following `resources/question-blocks.md` of project-onboarding, with:

- A concise summary question: "3 drifts detected against `.thrum/policy/philosophy.md`.
  Apply all, select, or decline?"
- Choices: `Apply all`, `Select items to apply`, `Decline (keep doc as-is)` (pick one)
- Include the full sectional diff from Step 3 in the block so the
  user can see what they're approving

If the user picks `Select items`, open a block of its own with
per-item yes/no choices.

### Step 5: Write only on confirmation

Apply approved edits in-place. For each applied edit:

- Preserve surrounding content (don't re-render the whole template)
- Append a provenance comment near the change:
  `<!-- updated YYYY-MM-DD via project-philosophy re-run-evolved -->`

Write the file once, at the end. Announce the applied items in the final
message.

### Step 6: On decline — no write + log

If the user declines (or selects zero items), do NOT write to the file. Record
the skipped proposal in `.thrum/policy/philosophy-skipped.jsonl` (append-only, one JSON
line per decline) with the timestamp and the drift items proposed. Show this line once:

> Say: I noted that you declined this, so it is not offered again.

The skip log means the declined items are not offered again: the drift step omits any item recorded in it.

Skipped-proposal log is advisory — its absence is not an error.

## Reference

- `.thrum/policy/philosophy.md` — the canonical doc this skill generates
- `resources/reliability-class-library.md` — the generalizable reliability
  class library Step 4a probes; shared with `project-hotpath-gate`
- `coordinator-philosophy-merge-gate` — the gate skill that reads the philosophy
  doc
- `project-hotpath-gate` — the companion builder that generates
  `.thrum/policy/hotpath-gate.json` (hot-path/perf gate config). Run both at the same
  onboarding moment so the project has both general philosophy and hot-path gate
  configuration from day one.
