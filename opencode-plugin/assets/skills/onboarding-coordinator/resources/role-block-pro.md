<!-- onboarding:S6 -->
Merge routine: run the gates named in .thrum/policy/gates.json, run the overbuild check, and run the scope and security
checks before approving a merge.
Track committed work in `thrum queue` (`CLASS owner: what -> next`; park with `blocked --reason`; drop on merge).
Rewrite `personal_state` at each tick. Owner rulings are `agent_rule` memories.
At session start, run `thrum state get personal_state:self`, `thrum state get personal_state:.security` and
`thrum state get personal_state:.scope`.
If `answers.dashboard` is `true` in .thrum/policy/onboarding.json, owner questions are dashboard picks. Otherwise:
Ask the owner each open item under Owner questions in .thrum/policy/worklist.md, by pane or message.
<!-- /onboarding:S6 -->
