---
name: project-gate-setup
description: "Use when a project needs its landing-gate configuration established or updated - the canonical config at .thrum/policy/gates.json naming the per-landing test, race and lint commands, the focused-versus-full rule, how to build the merged tree, the structural checks, the verdict log and the evidence retention the gate role follows. Detects Go, Node/TypeScript, Python and Rust from the repo, asks when unsure, and writes the file the gate role reads at gate time. Triggers - set up the gate, configure the gate role, gate config, what does the gate run, gates.json is missing, gate config missing."
---

# Project Gate Setup

## Missing policy files

This skill writes `.thrum/policy/gates.json`. When that file is absent the skill is in first-run mode, which is not a
miss. It reads no other policy file. When the gate role or a merge-gate skill finds `gates.json` missing, it prints the
notice below and names `onboarding-gates`, the skill that writes it through this one.

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

## History analysis

When .thrum/results/history-analysis.md is absent or stale, follow
history-analysis.md in the project-onboarding resources before the first block.

## Canonical path

`.thrum/policy/gates.json` — the single authoritative location. The gate role reads it at gate time. Its preamble names
no project command; every command comes from this file. A field left out means the gate falls back to asking, never to
guessing.

## Run modes and dispatch order

On every invocation, dispatch in this order. Earlier branches short-circuit later ones.

1. **First-run** (config absent) — generate `.thrum/policy/gates.json` from repo inspection and the answers below.
2. **Re-run-unchanged** (config present and matches the repo) — report "gates.json is current; no changes needed"
   and exit without writing.
3. **Re-run-evolved** (config present, repo has drifted) — compute a sectional diff, present it, write only on approval.

Load the /thrum:generator-idempotency-protocol skill and follow it.

> **Human in the loop.** The candidates below are proposals. The user confirms every command before it is written.

## First-run mode

### Step 1: Census the languages

Detect every language present; a repo can carry several. Record them as `languages_detected`.

- Manifest files at the repo root or in each workspace: `go.mod`, `package.json`,
  `pyproject.toml` / `requirements*.txt` / `setup.py` / `tox.ini`, `Cargo.toml`.
- `git ls-files` extension histogram as a cross-check, and as the only signal where a subtree has no manifest.
- A language counts when it has a manifest or clears 5% of tracked files. A polyglot repo gets a command set per language.

### Step 2: Read the project's own commands first

The project's own definition of "passing" outranks any default below. Read, in this order, and treat what you find as
ground truth:

1. CI workflow `run:` steps (`.github/workflows/*`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/config.yml`).
2. `Makefile` / `justfile` targets named `test`, `check`, `ci`, `lint`, `verify`.
3. `package.json` `scripts` (`test`, `lint`, `typecheck`, `build`); the lockfile picks the package manager
   (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lockb`). For workspaces, enumerate the packages.
4. `README` / `CONTRIBUTING` test instructions.

When `answers.inventory` is present in `.thrum/policy/onboarding.json`, read its `gate-command` and `hook` records too:

- Write a lane for each record decided `bring-in`, hooks included. A `.pre-commit-config.yaml` hook becomes
  `pre-commit run <id> --all-files`. A file in `.husky/`, or in the `core.hooksPath` directory, becomes that file's path,
  run with no arguments.
- Drop the commands left as `leave`.
- Ask no question the inventory already settled.

With no `answers.inventory` (this skill run alone), detect as above.

### Step 3: Propose commands per language

Defaults apply only where Step 2 found nothing. Each is a candidate the user confirms.

| Signal | Build / test candidates | Zero-match control |
|---|---|---|
| `go.mod` | `go build ./...`, `go vet ./...`, `go test ./...`; a race lane `go test -race ./...` when CI runs one; `golangci-lint run` only if a `.golangci.*` file exists | `go test -list '<selector>' ./pkg` plus a selector that must list nothing |
| `package.json` | the repo's own `test`, `lint`, `typecheck`, `build` scripts via the detected package manager | the runner's list mode (`--listTests`, `--list`) plus a selector that matches nothing |
| `pyproject.toml` etc. | `pytest` when configured; `ruff` / `mypy` only when configured | `pytest --collect-only -q <selector>` plus an impossible selector |
| `Cargo.toml` | `cargo build`, `cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check` | `cargo test <filter> -- --list` plus an impossible filter |

### Step 4: Ask what detection could not settle

Show every open question as a row, with the answer you propose from detection. Never pick silently between several
plausible commands.

Ask the rows as blocks, following `resources/question-blocks.md` of project-onboarding: head each block
`Block <i> of <k>: <topic>`, at most seven rows to a block, `Choices:` only on a pick row, and the reply line under the
block. `Recommended:` is the answer you propose from detection. `Why:` names the evidence: the file or command it came
from. A row with nothing detected uses the fallback `Why:` line from that file and the value in the "Fallbacks" table
of `resources/profiles.md` under "gate setup".

When the history read was skipped or found nothing,
put the History: line under every fallback line, as question-blocks.md says.

For the required per-landing test, recommend the command CI runs. With no CI command, recommend the first command
detected in the Step 2 order. The `Why:` line names the command and where it was found, so nothing is picked silently.
With nothing detected, the fallback applies: unset, listed as an owner question.

```text
Block 1 of 2: What the gate runs

1. Which command is the required test for every landing?
   Recommended: <the command CI runs, or the first command detected>
   Why: <the command, and the file it was found in>
2. Is there a separate race or sanitizer lane, and what time bound does it have?
   Choices: none / <the lane found> (pick one)
   Recommended: <the lane CI runs, or none>
   Why: <one line naming that evidence, or the fallback line>
3. Is any package or suite too large to run as one monolith? It goes under `never_monolithic` with the route to use.
   Recommended: <the suites found, or none>
   Why: <one line naming that evidence, or the fallback line>
4. Do any tests share fixed-name resources (ports, sockets, fixtures) that forbid parallel runs?
   Choices: yes: tests do not run in parallel / no (pick one)
   Recommended: <the answer the tests point to, or yes: tests do not run in parallel>
   Why: <one line naming that evidence, or the fallback line>

Reply "yes to all", tell me what to change (for example "1: make test"), say "not sure about 1", or ask "explain 1".
```

```text
Block 2 of 2: Files, checks and records

1. Which files are generated, and what regenerates each? Which baseline or ratchet files may the gate refresh for an
   already-reviewed pattern?
   Recommended: <the generated files and baselines found, or none>
   Why: <one line naming that evidence, or the fallback line>
2. Which targets write to source (formatters, `--fix` linters, code generators)? They go under `write_capable_targets`.
   Recommended: <the `fmt`, `format`, `--fix` and `lint-fix` targets found in the Makefile and package scripts, or none>
   Why: <one line naming that evidence, or the fallback line>
3. Which structural checks must pass for a change to be mergeable (generated-file drift, dependency or license checks,
   schema checks)?
   Recommended: <the checks found, or none>
   Why: <one line naming that evidence, or the fallback line>
4. Where does the one-line verdict record go?
   Recommended: docs/gate-log.md
   Why: <one line naming that evidence, or the fallback line>
5. Which directories hold gate output that is deleted once the verdict is decided?
   Recommended: <the directories found, or nothing kept>
   Why: <one line naming that evidence, or the fallback line>

Reply "yes to all", tell me what to change (for example "4: logs/gates.md"), say "not sure about 4", or ask "explain 4".
```

A ratchet brought in from the repository keeps the owner's own ceiling file as its `baseline_file`. Do not ask about
that file and do not add it to `baselines`: the owner's script owns it, so the gate never refreshes it.

When `answers.lane_scope` and `answers.topology` are present, prefill from them and ask nothing they settled:
`answers.lane_scope` picks whole-tree or changed-scope `per_landing` lanes, and `answers.topology` fills `runner`,
`gate_box` and `merge_king`.

### Step 5: Write `.thrum/policy/gates.json`

Fields (all optional; omit rather than leave empty):

| Field | Meaning |
|---|---|
| `languages_detected` | the Step 1 record |
| `build_merged_tree` | how to build the merged tree the gate judges: fetch, merge into a scratch worktree, build |
| `per_landing` | ordered `{name, cmd, kind}` list every landing runs (`kind`: build, test, race, lint) |
| `full_fallback` | what to run when test selection errors or cannot run |
| `focused_vs_full` | the rule: a selector run only localizes a failure; the verdict rests on the whole-lane run |
| `zero_match_check` | how to prove a selector ran something, with the control that must find nothing |
| `structural_checks` | `{name, cmd, why}` checks beyond tests |
| `generated_files` | `{pattern, regen_cmd}` the gate may regenerate as a bookkeeping commit |
| `baselines` | ratchet or baseline files the gate may refresh for an already-reviewed pattern |
| `write_capable_targets` | commands never to run on a tree anyone cares about |
| `never_monolithic` | packages or suites that must go through a sharded route |
| `shared_resources` | fixed-name resources that forbid parallel execution |
| `verdict_log` | the one committed record per gate |
| `retention_paths` | gate output deleted after the verdict |
| `per_landing_race` | `none`, `concurrency_only` or `full`; thrum's default is `concurrency_only`. A top-level key, because `per_landing` is already an array of lane commands |
| `batch.every_n_landings` | race the trunk tip every N landings; `0` means no batch race |
| `batch.cmd` | the command the batch race runs |
| `batch.required_for_deploy` | `true` when nothing deploys without a green batch race |
| `runner` | the agent that runs the gates, by its agent name (Solo: the coordinator's name), or `gate_agent` when the coordinator sends each gate to a gate-runner agent |
| `gate_box` | `local` (the gates run on the runner's own machine) or the name of the dedicated gate box; there is no `none` value, so without a dedicated box the value is `local` |
| `merge_king` | `{"from": "orchestration.merge_kings"}`; a pointer to the config key, never a copied name |
| `policy.unmeasured_findings_block` | `false` means a finding with no failing test or reproduction never blocks |
| `ratchets[]` | `{name, detector_cmd, baseline_file, waiver_tag}`; `waiver_tag` is always `RATCHET-WAIVER:`; `baseline_file` sits under `.thrum/policy/ratchets/` or, for a ratchet brought in from the repository, is the owner's own ceiling file |
| `tiers` | `{philosophy_lens: bool, hotpath_lens: bool}`; whether the owner chose each lens review in `onboarding-gates` Step 1. The merge skills read it before dispatching a lens gate; `false` means that gate is off, not missing |

Each `ratchets[]` entry runs as an `always_run` lens.
<!-- markdownlint-disable-next-line MD013 -->
The lens also fails when the landing's diff changes `baseline_file` and no commit message in the landing contains `waiver_tag`.
Any change counts, including a lower ceiling, because the ceiling's format is the owner's.

Examples per language are in `references/gates.go.json`, `gates.node.json`, `gates.python.json` and
`gates.rust.json`. Start from the one that matches, then replace every value with what Steps 2 to 4 settled.

`.thrum/policy/` is committed, unless Thrum is in stealth mode. Stealth mode is decided by
two steps. Run `git rev-parse --git-path info/exclude`, then `grep -qx '.thrum/' <the path it printed>`: exit 0 means
stealth mode. The exclude file holds a bare `.thrum/` line. In stealth mode, never edit .gitignore: Thrum's files stay
out of git there. Make no `.gitignore` edit and say nothing about it.

Outside stealth mode, if `git check-ignore -q .thrum/policy/gates.json` exits 0, say this first:

> Say: I am adding lines to .gitignore so that git tracks .thrum/policy/. The rest of .thrum/ stays out of git.

Then edit `.gitignore` to hold the lines `!/.thrum/`, `/.thrum/*` and `!/.thrum/policy/`. When `.gitignore` has a bare
`.thrum/` line, replace that line with these three lines: git cannot re-include a file under an ignored parent
directory, so a bare `.thrum/` line must go. Afterwards `git check-ignore -q .thrum/policy/gates.json` must exit 1.

Announce the path, summarize what was detected per language and which answers came from the user, then tell the user the
gate preamble picks the file up with no further step (its text only points at the file).

If Step 2 and Step 3 found no test command for a detected language, write no command for it, say so, and leave the
field out. The gate then reports that lane as `NOT RUN`.

## Re-run-unchanged mode

Triggered when `.thrum/policy/gates.json` exists. Read it in full, re-run Steps 1 to 3 comparing instead of writing, and
check each command still exists (script name, make target, CI step). If nothing differs, print
`.thrum/policy/gates.json is current; no changes needed` and stop. If anything differs, continue in evolved mode.

## Re-run-evolved mode

> **Never silently overwrite.** The file may hold answers only the user knew. A write without confirmation is a bug.

Drift categories: a language appearing or disappearing; a command whose script, target or CI step changed or vanished;
a new write-capable target; a new generated file or baseline; a changed verdict-log location.

Present each drift as a plain-language change, the proposed edit, and a one-line reason. On approval apply the edits in
place, preserving the rest. On decline write nothing and record the skipped proposal for the next run.

## Reference

- `.thrum/policy/gates.json` — the file this skill generates
- `references/` — one example per language
- `project-hotpath-gate` and `project-philosophy` — sibling generators for the hot-path lenses and the philosophy doc
- the gate role preamble — reads this file at gate time and raises the missing-policy alert (below) when it is missing
