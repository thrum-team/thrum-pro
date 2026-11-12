<!-- onboarding:alert -->

**Missing policy.** Do this before you read a policy file, and again whenever a
step needs a key from one.

1. Check that the file exists and has the key you need. A file that exists but
   lacks the key is a miss. A file whose writing section
   `.thrum/policy/onboarding.json` records as `undone` is a miss although the
   file is kept.
2. On a miss, when the owner is present, first say this, with `<part>` the part
   that writes the file, in plain words:

   <!-- markdownlint-disable MD013 -->

   > Say: I can't do this step yet: <file> is missing because the <part> has not
   > been set up. Run <skill> to add it.

   <!-- markdownlint-enable MD013 -->

   Then print
   `ONBOARDING MISSING: .thrum/policy/<file> [key <k>] (written by <skill>); run <skill>`.
   `<skill>` is the name of the skill that writes the file (for example
   `onboarding-gates`), never a section label. Leave out `[key <k>]` when the
   whole file is missing.

3. Message the coordinator with that line, unless you are the coordinator.
4. Stop the step that needs the file. Never continue with defaults. Never take
   the value from another record instead: `onboarding.json`'s `answers`, an
   earlier verdict, or what you remember of the file. Those record what was
   decided; only the file is the setting.
5. If `.thrum/policy/onboarding.json` records the section that writes the file
   as `skipped`, word the notice by its `reason`. It still stops:
   - `owner`:
     `ONBOARDING MISSING: .thrum/policy/<file> [key <k>] (owner-declined); run <skill> to add it`
   - `profile`:
     `ONBOARDING MISSING: .thrum/policy/<file> [key <k>] (skipped for the Solo profile; run <skill> to add it)`

   A section recorded `undone` gets the plain wording from step 2.

6. Check `reported` in `.thrum/policy/onboarding.json` first, and send a given
signature once: `missing:<file>` or `missing:<file>:<k>`, or
`skipped:<skill>:<reason>` when step 5 applies. After you send it, add it to
`reported`. If `onboarding.json` does not exist, treat `reported` as empty and
no section as skipped.
<!-- /onboarding:alert -->
