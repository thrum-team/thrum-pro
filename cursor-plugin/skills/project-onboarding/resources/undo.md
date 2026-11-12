# Undo

Undo reverses what onboarding installed, and nothing else. It reads `.thrum/policy/installed.md`, which lists each write
onboarding made outside `.thrum/policy/` and `.thrum/results/`. It never deletes a file that was yours before onboarding:
the originals of anything brought in are never touched, and only Thrum's own copies and entries can be removed. Run the
six steps in order.

## Undo step 1: Show

Read `.thrum/policy/installed.md` and show the owner every row whose `status` is `active`, with its kind, target and the
skill that wrote it. A row marked `removed <YYYY-MM-DD>` is already gone and is not shown. Ask the owner which rows to
undo, and do not remove anything yet.

## Undo step 2: Remove

Go through the rows the owner chose, by kind (the kinds are in the table in `onboarding-schema.md`):

- `monitor`: remove the monitor with `thrum monitor delete <id>`, using the id in `target`.
- `kept-monitor`: remove the row only. The monitor is the owner's and is never stopped.
- `role-block`: remove the marked block only. Read the role file, replace the text between the `<!-- onboarding:<owner> -->`
  and `<!-- /onboarding:<owner> -->` lines, markers included, with nothing, and write the whole file back.
- `agents-md-line`: remove the marked block from `AGENTS.md` or `CLAUDE.md` in the same way,
  together with the one blank line directly above its start marker, which the security section wrote with it.
- `config-write`: read the whole value with `thrum config show <key> --json` (its `value`). Restore the entry to the
  `prior` value, or delete the entry when `prior` is `absent`. Write the whole value back with
  `thrum config set <key> '<JSON>'`, and use `thrum config unset <key>` when a map would be left empty.
- `state-scope`, `memory-rule` and `copied-item`: remove the scope, memory or item the row names only on the owner's yes,
  and first offer a copy into the Free files (`.thrum/policy/rulings.md` or `.thrum/policy/worklist.md`).

Mark the row of each removed item `removed <YYYY-MM-DD>`. A row the owner keeps stays `active`.

A ruling that came from an import is reversed by its own row: on the Pro setup through its `memory-rule` row, so only on
the owner's yes. On the Free setup its line in `.thrum/policy/rulings.md` and the copies stay in `.thrum/policy/`; see
"Undo step 4: Keep". The `ratchets[]` entries and lanes in `gates.json` stay too. When a ruling made from an import is
removed, its `answers.inventory` record goes back to `pending`, so a re-run offers it again.

## Undo step 3: Tracker

List every `tracker-issue` row with the show command for its tracker: `bd show <id>` for `beads`, or
`thrum issue show <id>` for `native`. Never remove these issues. List every `imported-from` row too, and never remove
those either.

## Undo step 4: Keep

Leave `.thrum/policy/` and `.thrum/results/` in place unless the owner says to delete them. After Undo, `gates.json`
still parses.

## Undo step 5: Record

Mark each section `undone` in `.thrum/policy/onboarding.json`, so the skills raise the missing-policy alert again. There
is no old-path fallback, so that alert is the expected state after Undo.

## Undo step 6: Boundaries

Never change text outside a marked block.
