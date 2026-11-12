# Coupling report

Written by onboarding-coupling on <YYYY-MM-DD>, from <n> commits. The
measurement script is in .thrum/policy/coupling/. Review this file before you
push: this folder is committed with your code.

## Inventory

How many units the graph has, how many are tests, and how many edges come from
test imports alone. Worked example: "412 units, 138 of them tests; 1,870 edges,
190 of them only from test imports."

## Cycles

Each group of units that depend on each other, counting test imports, with its
size and the test-only edges that close the loop. Worked example: "one group of
46 units held together by 62 test-only edges. Cut those edges and the group
falls apart. With production imports alone there are no groups, which is the
control."

## Impact distribution

For each unit, how many test units re-run when it changes. Give the median, the
90th percentile and the worst case. Worked example: "median 31% of test units,
90th percentile 74%, worst case 100%."

## Size outliers

Units that are far larger than the rest, or that more units depend on than the
rest. Worked example: "one unit has 9,400 lines and 120 dependents; the median
unit has 210 lines and 6."

## Invisible coupling

Dependencies the import graph cannot see: a shared database, a port, a path that
depends on the repository root, a program started by a test, a generated file.
Worked example: "twelve tests start the same server on port 8080, so they cannot
run at once."

## 60-commit replay

For the last 60 commits (or all, when there are fewer): the median share of test
units a change re-tests, and the number of changes that fall back to a full run.
Changed-scope lanes are viable when the median is under 25% and fewer than half
of the changes fall back to a full run. Result: `coupling.changed_scope_viable`
is <true|false>.

## Questions the graph cannot answer

- Repository-root lookup: <answer>
- Shared databases and ports: <answer>
- Started programs: <answer>
- Lane time budget: <answer>

## Keep-separate rules

The rules the owner picked, each with the loop or outlier it keeps from coming
back.

## Work list

Each fix, with its step to measure again. When the owner declined the tracker,
or the tracker command failed, this is a checklist and `coupling.work_list` is
`coupling.md`.
