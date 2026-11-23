<!-- markdownlint-disable MD013 -->
# Profiles

`project-onboarding` writes `profile: solo` or `profile: team` after the preface. A section run alone leaves `profile`
unset and treats it as `team`, so it never applies a Solo value.

Each table row is one key: `| section | key | how | value |`. The `how` column is one of:

- `asked`: the owner is asked the question.
- `written`: the skill writes the value and asks nothing.
- `default offered`: the value is shown in a Solo accept-or-review table, and the owner accepts or reviews it.
- `appended`: the value is added to a list when something is found and brought in.

Every value that replaces a question the Solo run does not ask is listed below.

## Offers come first

Every section's offer comes first under both profiles. Its answer is recorded in `sections.<S>.status`, not as a key
row. Under Solo, the coupling section's offer defaults to "skip it for now", recorded with `reason: profile`. The owner
may still say "do it now".

## Solo

| section | key | how | value |
|---|---|---|---|
| security | `answers.security_depth` | asked | the owner's choice |
| security | `answers.deployment_shape` | asked | the owner's choice |
| security | `answers.external_calls` | asked | the owner's choice |
| philosophy | `answers.burn_down` | asked | the owner's list, `[]` when none |
| coupling | `sections.S3.status` | written | `skipped`, with `reason: profile` |
| coupling | `coupling.changed_scope_viable` | written | `false` |
| coupling | `coupling.source` | written | `"solo-default"` |
| coupling | `answers.ratchet_candidates` | appended | `[]` unless a found ratchet is brought in |
| gates | `answers.topology` | written | `solo` |
| gates | `orchestration.merge_kings` | written | the merge target's entry, set to the named coordinator; the whole map is written through `thrum config set` |
| gates | `runner` | written | the coordinator's agent name |
| gates | `gate_box` | written | `gate_box: "local"` |
| gates | `merge_king` | written | `{"from": "orchestration.merge_kings"}` |
| gates | `answers.hot_paths` | written | `[]` unless the hotpath step is chosen |
| gates | `tiers` | default offered | the per-landing lane only |
| gates | `tiers.philosophy_lens` | default offered | `false` |
| gates | `tiers.hotpath_lens` | default offered | `false` |
| gates | `answers.lane_scope` | default offered | `whole` |
| gates | `batch.every_n_landings` | default offered | `batch.every_n_landings: 0` |
| gates | `batch.cmd` | default offered | `""` |
| gates | `batch.required_for_deploy` | default offered | `false` |
| gates | `per_landing_race` | default offered | `concurrency_only` |
| gates | `retention_paths` | default offered | thrum's default |
| gates | `policy.unmeasured_findings_block` | default offered | `false` |
| checks | `answers.cadence` | default offered | from `suggest-cadence.sh` |
| checks | `checks.json` globs, size thresholds, stalled time and delivery | default offered | the check defaults; delivery is detected |
| coordinator | `answers.reminder_cadence` | written | `off`, unless the owner turns the reminder on |
| coordinator | `answers.dashboard` | asked | `false`, the default (offered only on Pro with `dashboard.write`) |
| coordinator | `answers.rulings` | appended | one entry for each ruling made by an earlier section |
| all | `answers.inventory` | written | one record for each found item, `decision: pending` |

- The checks section writes its keys after one accept-or-review question. The gates section's Step 3 values are
  `written`, and its Step 1, 2 and 4 values are shown in one accept-or-review table.
- The coordinator section follows its Solo item: the hourly reminder and the dashboard are offered, defaulting to off.
- The `answers.inventory` row is `written`. Its Solo question, asked once for each section that has found items and
  never when nothing was found, is:

> Ask: I found <n> things you already have that fit this part of the setup. Bring them all in, choose one by one, or leave them all?

## Team

Team sees every question, in blocks, each with a recommended answer. answers.inventory is written.

| section | key | how | value |
|---|---|---|---|
| security | `answers.security_depth` | asked | the owner's choice |
| security | `answers.deployment_shape` | asked | the owner's choice |
| security | `answers.external_calls` | asked | the owner's choice |
| philosophy | `answers.burn_down` | asked | the owner's list |
| coupling | `coupling.changed_scope_viable` | asked | measured, then confirmed |
| coupling | `coupling.work_list` | asked | `tracker` or `coupling.md` |
| coupling | `answers.ratchet_candidates` | asked | the owner's list |
| gates | `answers.topology` | asked | the owner's choice |
| gates | `orchestration.merge_kings` | asked | the merge target's entry |
| gates | `answers.lane_scope` | asked | the owner's choice |
| gates | `answers.hot_paths` | asked | the owner's list |
| gates | `batch.every_n_landings` | asked | the owner's choice |
| gates | `batch.required_for_deploy` | asked | the owner's choice |
| checks | `answers.cadence` | asked | the owner's choice |
| coordinator | `answers.reminder_cadence` | asked | the owner's choice |
| coordinator | `answers.dashboard` | asked | the owner's choice |
| coordinator | `answers.rulings` | asked | one entry for each ruling made by an earlier section |
| all | `answers.inventory` | written | one record for each found item, `decision: pending` |

## Consequences

- No carrier skill reads the coupling files. Only the gates section, which gets the written value, and the scope check,
  which reports "coupling not measured", depend on the coupling section.
- Changing from Solo to Team on a re-run needs nothing extra: the umbrella offers the coupling section again, as it
  does every skipped section.
- A skip with `reason: profile` is worded "skipped for the Solo profile; run onboarding-coupling to add it", not as
  owner-declined.

## Fallbacks

The fallback for a question is the value the part's skill offers as its default for the owner's profile. The questions
below have no such default, or are listed so that the value is in one place. Where a skill offers no default for the
Team profile, the fallback is the Solo value.

| Part | Question | Fallback |
|---|---|---|
| security | how deep the model goes | `Standard` |
| security | each actor: defend or not | `defend` |
| security | watch list | the patterns the scan proposes; none when the scan proposes none |
| engineering rules | mistakes to turn into rules | none added |
| coupling | the four questions the graph cannot answer | "not known", listed as an owner question |
| coupling | which keep-separate rules to enforce | none |
| inventory | each found item | `leave` |
| gate setup | the required per-landing test | unset, and listed as an owner question |
| gate setup | a separate race or sanitizer lane (not the per-landing race setting, which keeps its shipped default) | none |
| gate setup | suites too large to run whole | none |
| gate setup | generated files, and baselines the gate may refresh | none |
| gate setup | targets that write to source | the detected `fmt`, `format`, `--fix` and `lint-fix` targets; none when none is detected |
| gate setup | structural checks | none |
| gate setup | where the verdict record goes | `docs/gate-log.md` |
| gate setup | gate output kept after the verdict | nothing kept |
| gate setup | tests that share fixed-name resources | yes: tests do not run in parallel |
| hot-path review | which paths | none |
| configure-roles | which roles | the roles the detected setup already uses; otherwise coordinator and implementer |
| configure-roles | each role's autonomy | strict |
