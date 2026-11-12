---
name: configure-roles
description:
  "Detect environment and set up role-based preambles for your Thrum agents.
  Writes the shipped role templates to .thrum/role_templates/ and your project's
  own text into a configure-roles block of .thrum/policy/roles/<role>.md, which
  auto-apply on agent registration."
# source: claude-plugin/skills/configure-roles/SKILL.md
---

## Configure Roles

Generate role-based preamble templates customized to your project environment.
Templates auto-apply when agents register via `thrum quickstart`.

**Announce:** "Using configure-roles to set up preamble templates for your
team."

### Missing policy files

This skill writes preamble templates under `.thrum/role_templates/` and its own
`configure-roles` block in `.thrum/policy/roles/<role>.md` (the file is made if
absent). It reads `.thrum/policy/onboarding.json` for `answers.topology` and no
other policy file. `answers.topology` is optional prefill: when the file or the
key is absent, ask the team questions in Step 4 as usual. Any other missing
policy file or key is a miss for the alert below.

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

### CLI path (AI-free)

A plain-CLI alternative now exists for quick, scriptable role setup without
requiring an AI agent:

```bash
thrum roles configure --detect   # configures all roles from registered identities
thrum roles deploy                # re-renders preambles
```

This writes **verbatim shipped templates** (faithful ~90% solution, correct for
the upgrade use case). Use this skill (`$thrum:configure-roles`) for
environment-tailored roles — project-specific context such as `bd` block syntax,
MCP guidance, or custom scope wording, written into the role's `configure-roles`
block. The CLI and the skill coexist; the skill's output is a superset of the
CLI's.

### Step 1: Detect Environment

Run these commands and collect the output (suppress errors):

```bash
thrum runtime list 2>/dev/null          # Installed runtimes
git worktree list 2>/dev/null           # Worktrees and branches
bd stats 2>/dev/null                    # Beads task tracker state
thrum team --all --include-inactive --compact 2>/dev/null # Fleet roster, including offline, stale and retired agents
ls .claude/skills/ 2>/dev/null          # Installed Claude skills
thrum config show 2>/dev/null           # Thrum configuration
```

Also check:

- `.claude/settings.json` for MCP servers (context7, etc.)
- Existing rendered templates in `.thrum/role_templates/`
- Existing role rules: `thrum roles rules show <role>` for each role (this skill
  owns only its `configure-roles` block)
- `answers.topology` in `.thrum/policy/onboarding.json` (who merges, who runs
  the checks, on which machine). Whatever it settles (solo or team, the
  coordinator and the merge owner) is not asked again in Step 4.
- Current saved answers in `.thrum/config.json` under `role_config` (if any)

To inspect a shipped reference template, use the CLI shim — never read directly
from a filesystem path, since the binary may run from any directory:

```bash
thrum roles templates print coordinator-autonomous
thrum roles templates print orchestrator             # single-variant role
```

### Step 2: Report Findings

Summarize what you detected:

- Runtimes installed
- Worktrees and branches in use
- Whether beads is configured
- Current team composition (agents, roles, modules)
- Available MCP servers and skills
- Existing role templates (if re-running)
- Existing `role_config` in `.thrum/config.json` (if re-running)

### Step 3: Check for Existing Configuration

```bash
ls .thrum/role_templates/ 2>/dev/null
thrum config show 2>/dev/null | jq '.role_config' 2>/dev/null
```

If `role_config` exists, recommend the saved value in each row (see "Re-run
Behavior" below) so the user only has to confirm rather than re-enter every
choice.

### Step 4: Ask Questions

Ask these as blocks in plain text, following `resources/question-blocks.md` of
project-onboarding: "Block <i> of <k>: <topic>", numbered rows, each with
Choices, Recommended and Why. The Why line names the detected setup from Step 1
(runtimes, worktrees, team, existing `role_config`, `answers.topology`); a row
with no such evidence uses the fallback Why line from that file. Block 1 is the
roles (4a); block 2 is each role's autonomy and the scope (4b and 4c).

#### 4a: Team Structure

Row: "What roles does your team need?" (pick one set)

List the roles first, and offer only those:

```bash
thrum roles templates list      # one shipped template name per line
```

Each name is `<role>-strict`, `<role>-autonomous` or a bare role name (a
single-variant role such as `orchestrator`). Take the role set from that output,
not from memory. If `answers.topology` names the roles, recommend them.

Choices based on detected agents, plus common defaults:

- coordinator, implementer (most common)
- coordinator, implementer, planner, researcher
- coordinator, implementer, reviewer, tester
- Custom set

A role with `-strict` and `-autonomous` names gets the autonomy question in 4b;
a role with a bare name does not.

#### 4b: Autonomy Level Per Role

For each role selected that has strict and autonomous variants in the list, add
a row to the autonomy block: "What autonomy level for the {role} role?" (pick
one), with the detected team and existing `role_config` as the Why evidence.

- **Strict** — waits for coordinator instruction, limited scope
- **Autonomous** — can self-assign tasks, broader scope

#### 4c: Scope Rules

If multiple worktrees detected, add a last row to the autonomy block: "Should
agents be restricted to their own worktree?" (pick one), with the detected
worktrees as the Why evidence.

- **single_worktree** — strict scope boundaries
- **cross_worktree** — can read across worktrees

### Step 5: Generate Templates

For each role:

1. Read the shipped reference via the CLI shim:

   ```bash
   thrum roles templates print {role}-{autonomy}
   ```

   For `orchestrator`, omit the autonomy suffix (single-variant):

   ```bash
   thrum roles templates print orchestrator
   ```

2. Write the shipped text to `.thrum/role_templates/{role}.md` unchanged. Keep
   per-agent template tokens (`{{.AgentName}}`, `{{.Module}}`,
   `{{.WorktreePath}}`, `{{.CoordinatorName}}`, `{{.RepoRoot}}`) **literal** —
   they get substituted per-agent at deploy time, not at template-write time.
   Never put project text in the template body.

3. Write the project text into the role's own block, between
   `<!-- onboarding:configure-roles -->` and
   `<!-- /onboarding:configure-roles -->`, in one pass:
   1. Read the role file with `thrum roles rules show {role}`.
   2. Replace only this block, or append it if it is absent.
   3. Write the whole file back with `thrum roles rules set {role}` (content on
      stdin), then `thrum roles deploy`.

   The block holds the environment-specific text:
   - If beads detected: `bd` commands for Task Tracking
   - If MCP servers detected: Efficiency guidance
   - If specific skills detected: references to them
   - If worktree restrictions: the Scope wording

   <!-- onboarding:configure-roles -->

   Project-specific text for this role, from environment detection.
   <!-- /onboarding:configure-roles -->

4. Append one row to `.thrum/policy/installed.md` for each block written, with
   the kind `role-block` and the target `{role}:configure-roles`:
   `| <id> | role-block | {role}:configure-roles | — | — | — | configure-roles | active |`.
   Do this whether the skill runs alone or from `onboarding-coordinator`. A
   re-run that replaces a block adds no second row for it.

### Step 5b: Persist Answers

After writing the templates and blocks, persist the user's answers so other code
paths respect their choices and drift detection can flag plugin upgrades:

```bash
cat <<'EOF' | thrum roles save-config
{
  "schema_version": 1,
  "roles": {
    "coordinator": {"autonomy": "{{coord_autonomy}}", "scope": "{{coord_scope}}"},
    "implementer": {"autonomy": "{{impl_autonomy}}", "scope": "{{impl_scope}}"}
  }
}
EOF
```

`thrum roles save-config` writes `role_config` into `.thrum/config.json`, fills
`schema_version` / `plugin_version` / `configured_at` with sensible defaults if
absent, and backfills `rendered_hash` per role from the current shipped body
hash so `thrum prime` shows no drift hints.

The save is atomic and preserves every other top-level config key
(backup/daemon/identity/telegram) byte-identical.

### Step 6: Offer Deploy

If agents are already registered, ask as one row (Choices: yes / no,
Recommended: yes, Why: the registered agents found in Step 1) whether to deploy
now:

```bash
thrum roles deploy --dry-run    # Preview
thrum roles deploy              # Apply to all agents
```

### Re-run Behavior

When `role_config` exists in `.thrum/config.json` (the canonical record), load
the saved answers and use them as the **prefilled values** (each row recommends
"keep: <saved answer>") so the user only has to re-confirm rather than re-enter
every choice:

1. Show existing roles with their saved autonomy and scope.
2. Ask in a block what to change: add a role, modify an existing role, or remove
   one.
3. Only regenerate requested templates.
4. Always re-run `thrum roles save-config` so `rendered_hash` is refreshed and
   the saved `plugin_version` / `configured_at` reflect the current run.
5. Offer deploy for changes.

If the user wants to apply only template-content updates after a plugin upgrade
(no answer changes), point them at `thrum roles refresh` — it regenerates
rendered files from saved answers without asking any questions.

### Environment-Specific Customizations

| Detected             | Text for the configure-roles block                       |
| -------------------- | -------------------------------------------------------- |
| Claude Code runtime  | Add Task tool + sub-agent guidance to Efficiency section |
| Beads installed      | Add `bd` commands to Task Tracking, disable TodoWrite    |
| Thrum MCP server     | Add MCP tool references, CLI fallback for sub-agents     |
| Claude plugin skills | List installed skills with usage guidance                |
| Context7 MCP         | Add library docs guidance to Efficiency section          |
| Multiple worktrees   | Add worktree scope rules to the Scope section            |
