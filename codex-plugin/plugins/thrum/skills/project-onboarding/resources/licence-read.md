<!-- onboarding:licence -->

**Licence read.** Do this before the first question, every time this block runs.

1. Run `thrum license status --json` and rewrite the `licence` record in
   `.thrum/policy/onboarding.json` from it. Copy only `status`, `tier`,
   `capabilities`, `repo_capabilities` and `oss_grants`, and set `checked` to
   the current time. Never copy `registration_record`, `machine_id`,
   `repo_origin` or `repo_id`: the file is committed with the code. If the
   command fails, replace the whole record with
   `{checked, status: "unknown", capabilities: []}`, with no `tier` and no
   `oss_grants`.
2. Derive the variant. It is `pro` when `repo_capabilities` contains all three
   of `queue.write`, `state.write` and `memory.substrate`. Otherwise it is
   `free`. The skill never matches `oss_grants.repos[]` itself and never derives
   a repository id. Follow only that variant's instructions. Offer the dashboard
   only when the variant is `pro` and `repo_capabilities` also contains
   `dashboard.write`.
3. Never read a `licence` record left by an earlier run without refreshing it
   first.
4. If a Pro write is refused anyway, stop that step and print:

   > Say: Your licence no longer covers this step. Run onboarding-coordinator to
   > switch to the matching setup.

   Inside `onboarding-coordinator` itself, do not print that line. Run step 1
   again and continue with the variant it derives.
   <!-- /onboarding:licence -->
