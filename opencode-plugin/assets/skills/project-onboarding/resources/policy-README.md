# Project policy

This folder holds the rules your agents follow in this repository. It is written by the onboarding skills and read by
your agents and scripts. It is committed with your code, so review changes to it before you push. In stealth mode all
of `.thrum/` stays on this machine only.

Skills read policy only from this folder. If a file or a key a skill needs is missing, the skill prints one
`ONBOARDING MISSING` line, tells the coordinator, and stops that step instead of guessing. Run the skill named in the
line to write the file.

## Files

Each row names the file, who writes it, and who reads it.

| Path | What it holds | Written by | Read by |
|---|---|---|---|
| `.thrum/policy/README.md` | this index | `project-onboarding` | everyone |
| `.thrum/policy/onboarding.json` | progress record: which sections are done, the answers that drive later sections, the licence record, the installed variant, the notices already sent | every onboarding skill, each its own entries | every onboarding skill, the check scripts |
| `.thrum/policy/security-model.md` | the security model, the owner's non-goals, and the watch list | `onboarding-security` | `project-philosophy`, `onboarding-gates`, `onboarding-checks`, the security check |
| `.thrum/policy/philosophy.md` | the project's rules and anti-patterns; `onboarding-coupling` owns one marked block in it | `project-philosophy`, `onboarding-coupling` | implementers, reviewers, `coordinator-philosophy-merge-gate` |
| `.thrum/policy/philosophy/` | topic documents that `philosophy.md` points to | `project-philosophy` | implementers, reviewers |
| `.thrum/policy/coupling.md` | the coupling report, the keep-separate rules, the work list | `onboarding-coupling` | `onboarding-gates`, the coordinator |
| `.thrum/policy/coupling/` | the measurement script, kept so a re-measure is comparable | `onboarding-coupling` | `onboarding-coupling` |
| `.thrum/policy/gates.json` | the merge-gate configuration | `onboarding-gates` through `project-gate-setup` | `coordinator-merging-code`, `coordinator-full-gate`, the merge-gate skills |
| `.thrum/policy/hotpath-gate.json` | the hot-path gate configuration, when you chose one | `onboarding-gates` through `project-hotpath-gate` | `coordinator-hotpath-merge-gate` |
| `.thrum/policy/ratchets/` | ratchet baselines | `onboarding-gates` | the merge-gate skills |
| `.thrum/policy/checks.json` | the periodic checks and their cadence | `onboarding-checks` | `onboarding-coordinator`, the check scripts |
| `.thrum/policy/checks/` | the check scripts, plus the coordinator's dash-tick script | `onboarding-checks`, `onboarding-coordinator` | the monitors that run them |
| `.thrum/policy/roles/` | one file per role, `roles/<role>.md`, holding that role's rules; each onboarding skill owns one marked block in it | `onboarding-security`, `onboarding-coordinator`, `configure-roles` | every agent of that role |
| `.thrum/policy/installed.md` | the list of what onboarding installed outside this folder, one row each, naming the skill that wrote it, so Undo can reverse it | `onboarding-coordinator` and every section that writes outside this folder | Undo, `onboarding-coordinator` |
| `.thrum/policy/worklist.md` | the work list (`## Work`) and open owner questions (`## Owner questions`), on the Free setup, and the owner questions on the Pro setup | `onboarding-coordinator`, the coordinator | the coordinator, the hourly reminder |
| `.thrum/policy/rulings.md` | one line per owner ruling, on the Free setup | `onboarding-coordinator` | every role, through its role file |
| `.thrum/policy/imported/` | copies of rules and notes you chose to bring in: `imported/rules.md`, and files under `imported/notes/`. The originals are never changed | `project-philosophy` and `onboarding-coordinator` | `onboarding-coordinator`, which turns each entry into a ruling |
| `.thrum/results/` | local results: `coordinator-state.md` and the latest `reports/<check>.md` | the coordinator, the check scripts | the coordinator |

`.thrum/policy/` is committed, so every checkout, worktrees included, reads its own copy at the checkout root.
`.thrum/results/` is local and, from a worktree, is resolved through `.thrum/redirect`. In stealth mode a worktree has
no `.thrum/policy/` copy; skills there resolve it through `.thrum/redirect`.

## Skills

Each section has its own skill. Every one can run alone, and `project-onboarding` runs all of them in order and picks
up where you left off.

| Section | Skill | What it writes | Runs alone |
|---|---|---|---|
| all sections in order | `project-onboarding` | `README.md`, `onboarding.json` | yes |
| Security | `onboarding-security` | `security-model.md`, a block in each role file under `roles/` | yes |
| Philosophy | `project-philosophy` | `philosophy.md`, `philosophy/`, `imported/` | yes |
| Coupling | `onboarding-coupling` | `coupling.md`, `coupling/`, a block in `philosophy.md`, work-list issues in your tracker | yes |
| Gates | `onboarding-gates` | `gates.json`, `hotpath-gate.json`, `ratchets/` | yes |
| Periodic checks | `onboarding-checks` | `checks.json`, `checks/` | yes |
| Coordinator memory | `onboarding-coordinator` | `roles/`, `installed.md`, `worklist.md`, `rulings.md`, `imported/`, monitors, and on the Pro setup the coordinator's queue, state and memory | yes |

## Marked blocks

Where a skill shares a file with another skill or with you, it owns only a block between
`<!-- onboarding:<owner> -->` and `<!-- /onboarding:<owner> -->`. It rewrites that block and leaves everything else in
the file alone, so your own text is never overwritten.
