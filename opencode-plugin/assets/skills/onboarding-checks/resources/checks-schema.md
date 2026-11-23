# checks.json

`.thrum/policy/checks.json` holds the settings every check script reads. It is committed with the code. The scripts
read it through `load_config` in `lib.sh`. A missing file, or a missing key, is a miss: `missing_notice` sends
`missing:checks.json` or `missing:checks.json:<key>` once, and the check stops without a report. The "Default" column
is the value `onboarding-checks` offers and writes, never a value a script falls back to; `coordinator` has none and is
written by `onboarding-coordinator`, so its absence is reported against that skill. Two keys are exempt: `deliver_to`
resolves to the merge king when absent, and `dashboard_generator` is optional.

| Key | Holds | Default |
|---|---|---|
| `cadence_hours` | how often the monitors run the checks, in hours | `24` |
| `branch_globs` | the branch-name prefixes the scope check watches | `["fix/", "feature/", "feat/", "refactor/", "test/"]` |
| `size_threshold.lines` | a branch is large above this many changed lines | `300` |
| `size_threshold.files` | a branch is large above this many changed files | `15` |
| `stalled_hours` | a branch with no commit for this many hours is stalled | `6` |
| `test_globs` | the repository's test-file patterns | `["*_test.go", "*.test.*", "*.spec.*", "test_*.py", "tests/"]` |
| `delivery` | how a report reaches its recipient: `auto`, `pane` or `inbox` | `auto` |
| `deliver_to` | the agent that receives reports | the merge king of the merge target, `orchestration.merge_kings[<merge target>]`; under Solo that is the coordinator named in the gates section |
| `coordinator` | the agent that ran `onboarding-coordinator`; the dash tick and the hourly reminder go to it | none; written by `onboarding-coordinator` |
| `merge_target_from` | the `thrum config` key that names the merge target | `orchestration.merge_target` |
| `security_doc` | the security model the security check reads | `.thrum/policy/security-model.md` |
| `dashboard_generator` | the command that refreshes the dashboard, when there is one | none; optional |

## Delivery

- `auto` uses the recipient's tmux pane when it has a live session, and the inbox otherwise.
- `pane` does the same; a pane that cannot be reached falls to the inbox.
- `inbox` always uses the inbox.
- Delivery is the same on the Free and the Pro setup.

When `deliver_to` is absent and `orchestration.merge_kings` has no entry for the merge target, the script prints
`ONBOARDING MISSING` for `orchestration.merge_kings`, tells the coordinator once, and sends nothing.

## Reports

Every run that delivers also overwrites `.thrum/results/reports/<check>.md` with its report. `.thrum/results/` is local;
from a worktree it is resolved through `.thrum/redirect`.

```json checks-example
{
  "cadence_hours": 24,
  "branch_globs": ["fix/", "feature/", "feat/", "refactor/", "test/"],
  "size_threshold": { "lines": 300, "files": 15 },
  "stalled_hours": 6,
  "test_globs": ["*_test.go", "*.test.*", "*.spec.*", "test_*.py", "tests/"],
  "delivery": "auto",
  "coordinator": "coordinator_agent",
  "merge_target_from": "orchestration.merge_target",
  "security_doc": ".thrum/policy/security-model.md"
}
```
