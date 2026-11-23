# Installed by onboarding

What onboarding wrote outside `.thrum/policy/` and `.thrum/results/`, one row each, so Undo can reverse it. Each row names
the skill that wrote it. A re-run updates `active` rows and never adds a duplicate.

| id | kind | target | prior | schedule | script | section | status |
|---|---|---|---|---|---|---|---|

The kinds are exact strings:

- `monitor`
- `kept-monitor`
- `role-block`
- `state-scope`
- `memory-rule`
- `config-write`
- `agents-md-line`
- `copied-item`
- `tracker-issue`
- `imported-from`
