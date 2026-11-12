# Role Bundle Layout

A role bundle is one folder, packed into one zip for install. The folder is the source you keep and revise. This file
is the layout the pack and install checks accept.

## Tree

```text
<bundle-folder>/
  manifest.json
  role/
    <role>-strict.md        # at least one of these two files
    <role>-autonomous.md
  skills/
    thrum-<role>-<skill>/
      SKILL.md
      <other files the skill needs>
```

Nothing else is allowed at the top level or inside `role/` or `skills/`. Pack and install name any other entry as an
error. Do not include `__MACOSX` entries, and do not wrap the folder in an extra folder: zip the folder's contents, not
the folder.

## manifest.json

```json
{
  "format_version": 1,
  "name": "<role>",
  "version": "1.0.0",
  "description": "One line on what the role does.",
  "suggested_models": {
    "claude": {"model": "<model id>", "effort": "<effort>"}
  }
}
```

| Field | Rule |
| --- | --- |
| `format_version` | Must be `1`. A higher number is refused. |
| `name` | Required, non-empty. Must equal the role name in every file name under `role/`. |
| `version` | Required, non-empty. Free text such as `1.0.0`. |
| `description` | Optional. Shown in the Roles list. |
| `suggested_models` | Optional. Maps a runtime name to `{model, effort}`. A malformed entry is dropped with a message and never fails validation. |

Unknown fields are ignored. Do not add machine-specific values here.

## Role name

- Only lower-case letters, digits, `_` and `-`.
- Must not end with `-strict`, `-autonomous`, `-ephemeral` or `-worktree-write-only`.
- Must not be a shipped role name. See the table of shipped roles in SKILL.md step 2.
- Must not be a retired role name. Pack reports the reason for any refusal.

A role name may contain `-`, for example `ops-acme`.

## Role files

- `role/<role>-strict.md` and `role/<role>-autonomous.md`. Provide one or both. A one-mode bundle is valid.
- The file name prefix must equal `manifest.json` `name`.
- Each file must parse as a Go `text/template`. Keep the placeholders the base role uses (for example `{{.AgentName}}`,
  `{{.Role}}`, `{{.Module}}`, `{{.WorktreePath}}`) unless the owner removes them on purpose.
- The first mode installed is `strict` when a strict file exists, otherwise `autonomous`. The owner's autonomy setting
  decides which file renders.
- `ephemeral` and `worktree-write-only` files are not offered for bundles.

## Skills

- Each skill is one folder `skills/thrum-<role>-<skill>/`.
- `<skill>` is non-empty and uses the same characters as a role name.
- The folder holds `SKILL.md` and any other files the skill reads.
- `SKILL.md` starts with YAML frontmatter that has:
  - `name`: a string equal to the folder name exactly.
  - `description`: a non-empty string. Use one line in double quotes, with no `": "` inside it.
- The body follows the frontmatter, with an H1 heading.
- A skill folder must not contain `.gitignore` or `.thrum-role-bundle.json`. The launch step writes both, so pack and
  install refuse a folder that already has them.

Example skill folder:

```text
skills/thrum-ops-acme-release-notes/
  SKILL.md
  template.md
```

```text
---
name: thrum-ops-acme-release-notes
description: "Use when writing release notes for the acme team - turns merged beads into a changelog section"
---

# Release Notes

Steps the skill runs, in order.
```

## Machine-specific additions

Role Rules are not part of the bundle. Pack and install never read or write them. Each machine adds its own
Role Rules in the existing Role Rules tab, and they appear in that machine's rendered role preamble.

## Validation limits

Pack and install check the zip and its contents against these limits:

- The zip is at most 10 MB.
- The zip holds at most 1,000 entries.
- Each entry is at most 5 MB.
- The unpacked total is at most 50 MB.

Pack and install also apply the manifest, role and skill rules above. A refusal names the offending entry and the rule
it broke.
