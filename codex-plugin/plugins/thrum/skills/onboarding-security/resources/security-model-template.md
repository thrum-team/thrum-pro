# Security model

Written by onboarding-security on <YYYY-MM-DD>. Review it before you push: this
folder is committed with your code.

Tiers: Light includes the governing sentence and the non-goals. Standard adds
the trust boundary and the in-scope table. Deep adds the boundary table and the
known gaps. Each heading below says which tiers keep it; delete the tier notes
when you fill the file in.

## Governing sentence

Tiers: Light, Standard, Deep.

One sentence that says what is trusted and what is protected. Example shape:
"The trust boundary is <what is
trusted>; everything inside it is not defended against, and everything outside
it is."

## Trust boundary

Tiers: Standard, Deep. Standard writes one paragraph. Deep adds the table below.
Light leaves this heading out.

One paragraph: where the boundary sits, who or what is inside it, and the
deployment shape it rests on.

| Boundary   | What crosses it | Control                   |
| ---------- | --------------- | ------------------------- |
| <boundary> | <what crosses>  | <control, with file:line> |

## In scope

Tiers: Standard, Deep. Light leaves this heading out.

What the system does defend, with the mitigation already in place.

| Threat   | Mitigation   | file:line   |
| -------- | ------------ | ----------- |
| <threat> | <mitigation> | <file:line> |

## Non-goals

Tiers: Light, Standard, Deep.

Each non-goal is a prose prohibition that tells a reader what not to build or
flag, with the date and the owner who ruled it. It is not a gap, not a
limitation and not deferred work.

- <YYYY-MM-DD>. <Prohibition, for example: "This project does not defend against
  X. Do not build Y.">

Close with one paragraph that says where these stop: <it says what the non-goals
do not cover, so a reader knows which threats are still in scope and where the
owner's ruling ends>.

## Known gaps

Tiers: Deep. Light and Standard leave this heading out.

Each gap is something the system should do and does not yet. Link each one to an
issue.

- <gap> (<issue link>)

---

The watch list below is read by the security check. Edit it only through
onboarding-security.

```yaml onboarding-watch-list
non_goals_confirmed: false
watch: []
```
