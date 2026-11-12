> <!-- markdownlint-disable MD013 MD028 -->

## Full form

> Say: This sets up Thrum for this repository. When it is done, your agents work
> to your rules, and this agent becomes the coordinator that checks their work
> before it lands. It takes about 40 minutes for one person and about 55 minutes
> for a team, and you can stop after any part.

> Say: It writes files in .thrum/policy/ and notes in .thrum/results/, and
> changes none of your code. It asks before it touches anything else, such as
> .gitignore or AGENTS.md. Checks and the coordinator are set up only in the
> last two parts, if you say yes.

> Say: What I read in this repository goes only to the AI service this session
> already uses.

> Say: Solo: you are the only person who reviews and merges here, however many
> agents you run. Solo asks fewer questions: I recommend each part's settings
> and you accept or change them. Team: other people review or merge too. You see
> every setting, with a recommended answer for each.

> Ask: Are you setting this up for yourself (Solo) or for a team (Team)?

## After the answer

> Say: The setup files in .thrum/policy/ are committed with your code, so review
> them before you push.

> Say: This repository is in stealth mode, so Thrum's files stay on this machine
> and are not committed.

## Short form

> Say: This scan reads the files in this repository only. It does not run your
> code. What it finds is written to .thrum/policy/security-model.md, which is
> committed with your code.

> Say: What I read in this repository goes only to the AI service this session
> already uses.

> Say: This section writes .thrum/policy/security-model.md, a block in each role
> file under .thrum/policy/roles/, and its progress in
> .thrum/policy/onboarding.json.

> Say: The other sections can follow later: run project-onboarding to be offered
> each one, or run a section's skill on its own.
