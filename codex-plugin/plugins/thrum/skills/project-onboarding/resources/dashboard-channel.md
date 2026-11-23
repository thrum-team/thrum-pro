# Dashboard channel

How the interview lets the owner answer a block in the dashboard instead of the
terminal. Read this once, after the licence read, and again at the start of
every block when the channel is `dashboard`. `resources/question-blocks.md`
still decides what a block holds. This file decides only where it is shown and
answered.

## When to offer it

Offer the dashboard only when all three hold: the variant is pro and
repo_capabilities contains dashboard.write; you are a registered Thrum agent in
a Thrum tmux session; and thrum dashboard show succeeds.

Otherwise say nothing about the dashboard.

The offer, with `<address>` taken from the `ui` line that `thrum daemon status`
prints:

<!-- markdownlint-disable MD013 -->

> Ask: I'll put each set of questions in the Dashboard tab of the Thrum web UI
> at <address>, with the recommended answers on buttons, and you can add a note
> to any answer. Say "terminal" if you'd rather answer here, or "ok" to go on.

<!-- markdownlint-enable MD013 -->

"Terminal" or "here" is `terminal`; anything else is `dashboard`.

Write the choice to answers.interview_channel. The owner may change it at the
start of any block.

This choice is not answers.dashboard, which decides where the coordinator puts
owner questions after onboarding.

## Publishing a block

Publish a block as one card, which names the part, the block and what it sets
up, followed by one pick per question.

The first button of every pick is the recommended answer, labelled
"(recommended)". The last button is "Other, see my note". Every pick allows a
note. A value that is not on a button is given in the note.

The other choices follow it as buttons, before "Other, see my note".

A pick-several question is one pick: its first button is the recommended set,
and the note takes a different set.

A free-text question is one pick too: its first button is the text you propose,
marked as recommended, and the note takes different text. The accept-all pick
has the one button.

Put the question's `Why:` line under the question in the pick's prompt. Start
that line with the word "Why:", as in the terminal form. "Explain <n>", the
say-back before writing and an answer of "I do not know" are handled in the
terminal, as `resources/question-blocks.md` says.

The first pick on the board is "Accept every recommendation in this block".

Keep the board within eight picks: when it already holds open picks, cut the
block shorter.

Resolved picks, and picks that something else put there, count until they are
deleted.

Make the ids of each block unique to that block, such as onb-<part>-<block>-<n>,
so that an old answer never matches a new pick. Publish with
`thrum dashboard set` and never with `--replace`, so that other widgets stay.

Give every widget of a block an id that starts onb-. When the block is settled,
mark its picks resolved and delete its widgets by id. Never clear the board.

## Waiting and settling

After publishing a block, say this, then end the turn:

<!-- markdownlint-disable MD013 -->

> Say: The questions for this part are waiting in the dashboard. You can also
> answer them here.

<!-- markdownlint-enable MD013 -->

Each answer arrives as a message that wakes you. Then read
`thrum dashboard results`.

Record every answer read from the board in answers_source: the recommended
button is accepted, any other button or a note is chosen. Text the owner typed
beside a button is that row's note.

A block is settled when "Accept every recommendation in this block" is picked or
every question has an answer. Accepting all applies only to the questions with
no answer of their own. The first complete answer to a question stands.

An answer that arrives after the block was settled is a change: say it back and
apply it once the owner confirms.

A terminal reply to an open board settles the rows it names; the rest stay open
on the board.

The durable record is `.thrum/policy/onboarding.json`, not the board.

If the terminal and the dashboard disagree on a question, show both answers and
ask which stands.

## When a write is refused

On a refused write, set `answers.interview_channel` to `terminal`, carry on with
the block in the terminal, and say this once:

<!-- markdownlint-disable MD013 -->

> Say: I could not write to the dashboard, so I am asking here in the terminal
> from now on.

<!-- markdownlint-enable MD013 -->

## A worked board

This board holds a card, the accept-all pick and two question picks, one
pick-one and one pick-several. Publish a board of this shape with
`thrum dashboard set --doc-file <file>`.

```json
{
  "title": "Setup questions",
  "widgets": [
    {
      "id": "onb-security-1-card",
      "type": "card",
      "title": "Security part, block 1 of 2: how deep the model goes",
      "body": "These two questions set how detailed the security model is."
    },
    {
      "id": "onb-security-1-accept",
      "type": "action-pick",
      "question_id": "onb-security-1-accept",
      "prompt": "Accept every recommendation in this block",
      "options": [
        { "id": "accept", "label": "Accept every recommendation in this block" }
      ],
      "allow_text": true,
      "status": "open"
    },
    {
      "id": "onb-security-1-depth",
      "type": "action-pick",
      "question_id": "onb-security-1-depth",
      "prompt": "1. How deep should the security model go? (pick one)\nWhy: A deeper model costs more to write and to keep current.",
      "options": [
        { "id": "standard", "label": "Standard (recommended)" },
        { "id": "brief", "label": "Brief" },
        { "id": "thorough", "label": "Thorough" },
        { "id": "other", "label": "Other, see my note" }
      ],
      "allow_text": true,
      "status": "open"
    },
    {
      "id": "onb-security-1-actors",
      "type": "action-pick",
      "question_id": "onb-security-1-actors",
      "prompt": "2. Which of these should agents defend against? (pick several)\nWhy: Each actor you pick adds guards that cost work to maintain.",
      "options": [
        {
          "id": "recommended-set",
          "label": "A stranger on the network and a leaked key (recommended)"
        },
        { "id": "everyone", "label": "Every actor in the list" },
        { "id": "other", "label": "Other, see my note" }
      ],
      "allow_text": true,
      "status": "open"
    }
  ]
}
```
