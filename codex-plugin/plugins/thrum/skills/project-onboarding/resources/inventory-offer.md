<!-- markdownlint-disable MD013 -->
<!-- onboarding:inventory -->

**Bring in what you already have.** Offer the items the inventory found for this
section, never an item it skipped.

1. Offer each `answers.inventory` record whose `offered_in` is this section and
   whose `decision` is `pending`. With no `answers.inventory`, offer nothing. A
   `security-note` record is not offered: the security section reads it into the
   scan report and sets it `prefilled`.
2. Before the first copy is written, show the committed-copies line, unless
   `reported` already holds the signature `imported-copies`. After showing it,
   add that signature to `reported`.

   > Say: What you bring in is copied into .thrum/policy/imported/, which is
   > committed with your code.

   In stealth mode, leave out the words about being committed with your code
   from every notice.

3. Team offers the part's found items as blocks in the form of
   `resources/question-blocks.md`, one row per item, or one row per file when
   the file has more than seven found items. A file with more than seven found
   items is one row. On that row, "choose one by one" opens its own blocks. Each
   row has the choices bring in / leave, `Recommended:` is `bring in`, and
   `Why:` says in one line what the item is. When you cannot say what an item
   is, recommend "leave" and use the fallback line. `<n>` on a file row never
   counts an item skipped as a credential.

   Solo asks one table question per section that has found items, covering all
   of them, and asks nothing when nothing was found. On that question, "choose
   one by one" opens blocks:

   > Ask: I found <n> things you already have that fit this part of the setup.
   > Bring them all in, choose one by one, or leave them all?

4. When a ratchet script has only a guessed ceiling file, Team makes the ceiling
   a row of the block, in the same row form: the question is whether `<file>` is
   the ceiling that `<script>` checks against, the choices are yes / no,
   `Recommended:` is `yes`, and `Why:` names the file as the nearest checked-in
   data file to the script.

5. A ruling made from a brought-in item has these fields:
   - `trigger` is "working in this repository".
   - `rule` is the item's first line, without its list marker. For a whole-file
     note, it is the file's first heading, or failing that its first line.
   - `applies_to` is `all`.
   - `from` is `<section title>, imported/rules.md#i-<n>`, and the `rulings.md`
     line renders it as written. The full text stays in the copy.
6. After the copies are written, a section that wrote at least one copy shows
   this line once, as the last action of the copy step: the copy step is not
   finished until the line below is shown. A section that copied nothing does
   not show it, and a ratchet brought in is not a copy, so it does not count.

   > Say: Thrum's copy in .thrum/policy/imported/ is now the one to edit. Your
   > original is untouched and is still read by any tool that reads it today, so
   > a rule you change in one place should be changed in the other. A full
   > re-run notices a changed original and offers to refresh the copy.

   <!-- /onboarding:inventory -->
