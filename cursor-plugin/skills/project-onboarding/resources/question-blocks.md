# Question blocks

How every part of the interview asks its questions. Read this before the first block of a part.

## The form

Never ask a run of related questions one at a time. Ask them as a block.

Write a block as plain text in your reply and wait for the owner's answer.

Show one block, then end your turn. Never show two blocks, or a question and a block, in one reply.

Do not use a question tool for a block: the tools differ between runtimes, some drop options, and an open question
can hold incoming messages.

A block holds at most seven questions; aim for five. Head each block "Block <i> of <k>: <topic>".

No recommendation may depend on an answer in the same block.

On a pick-one or pick-several row, list the choices on a Choices: line and say which kind it is. A free-text row has no
Choices: line.

For a free-text row, the recommendation is the text you propose. For a pick-several row, it is the set you propose.

A block is a numbered list, not a wide table, so that it reads in a narrow terminal.

A part with more than seven questions splits them into blocks by topic, in the part's own order.

A question whose recommendation depends on another answer goes in a later block than that answer.

Many like items are one row. "Choose one by one" on that row opens a block of its own.

Write each block in this form:

```text
Block <i> of <k>: <topic>

<n>. <question, in plain words>
   Choices: <a> / <b> / <c> (pick one)
   Recommended: <answer>
   Why: <one line naming the evidence>

Reply "yes to all", tell me what to change (for example "3: weekly"), say "not sure about 3", or ask "explain 3".
```

When every row of a block is a fallback, say the fallback line once under the block heading and leave out the Why:
lines.

When the history read was skipped or found nothing,
put the History: line from history-analysis.md under every fallback line, and under the one fallback line
when it is said once for the whole block.

## The reply

"Yes to all" accepts every recommendation shown in the block.
"Yes to all except 3 and 5", with the new values, changes those rows and accepts the rest.

Any other reply is read row by row.

"Explain <n>" gets a plain explanation of that row, and then the block is asked again.

A row the reply does not settle is asked again on its own; it is never taken as accepted.

A value that is not one of the row's Choices is not an answer: show that row's choices again and ask. Never drop a row.

Before writing, say back each answer that is not the recommendation, and wait for the owner to confirm.

"Not sure about <n>", or any reply that says the owner does not know, takes the recommendation for that row and
records it as unsure.

Keep a note the owner adds to a row with that row's answer, in answers_notes.
Write the note as typed, whatever it says, in the same write as the row's answer.
If the note asks for something you cannot do, say so and still write the note.

After a block in which the owner turned a protection off (a "do not defend", a gate or check left out), show this line
and then one line per such row:

> Say: You turned these off. Tell me which, if any, you want back on:

## The recommendation

Every question in a block has a recommended answer, taken from the repository, the inventory, any history analysis
and the earlier answers. The `Why:` line names that evidence.

No evidence in this repository; this is Thrum's default.

That is the exact `Why:` line for a fallback. The recommendation is then the fallback value listed for the question in
`resources/profiles.md`, under "Fallbacks".

Never write a reason of your own for a fallback value.

The rule behind the fallback values: keep the protection (security rows recommend "defend"), change less (inventory
rows recommend "leave"), and otherwise use the Solo value for that setting.

Recommend "do not defend" only when a security note found in this repository names that non-goal.

## What is recorded

Write a block's answers together, when the block is settled. Ask an interrupted block again whole.

Record each answer in `answers_source` as `chosen`, `accepted` or `unsure`, as `resources/onboarding-schema.md` says.
A recommendation taken by name or by "yes to all" is `accepted`.

The key for a row, in answers_source and in answers_notes, is the one its part's skill names for that row. When one row
is shown as several and its key has no <n> or <job> in it, add `_<n>` to its key. Never write an answer's source or an
owner's note under any other field.

A found-item row (bring in / leave) has no key here: its answer is its answers.inventory decision.
A row its part names no key for is recorded in neither.

On a re-run, a question that already has an answer recommends that answer, as "keep: <answer>".
When the evidence now points to a different answer, show both.

On a re-run of a part, first list that part's answers marked unsure and offer to settle them.
