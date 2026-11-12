# History analysis

How the interview reads this repository's git history, so that its
recommendations rest on evidence. Read this before the first block of any part.
It reads the repository and writes only its notes file.

## When it runs

The umbrella skill runs it once, after the preface and before the first part's
offer. A part run alone runs it when `.thrum/results/history-analysis.md` is
absent or stale. The file is local, so a fresh clone has none and runs it.

## What to say first

Ask this before the analysis runs, each time it runs, and stop for the owner's
reply. "Skip" or "no" means skip. Any other reply means go on.

If the owner says skip, run no pass. Write the result file with the result
"skipped by the owner", and do not offer the read again until a full re-run.

After a skip, the parts use the fallback recommendations, and the History: line
says the read was skipped. After a skip, read no commit for the rest of the
interview: no git log, git show or git rev-list, by you or by a sub-agent, and
cite no commit in any row.

A skipped result file has the word skipped where the commit sha goes, so the
staleness rule below does not make it due. A full re-run, which is running the
whole interview again, replaces it.

The question:

<!-- markdownlint-disable MD013 -->

> Ask: Next I read this repository's git history for areas that were fixed more
> than once for security or for speed, so I can recommend answers instead of
> asking you to remember. I read commit messages and file paths only, and keep
> my notes in .thrum/results/history-analysis.md on this machine; I never commit
> that file. This takes a minute or two. Say "skip" and I'll use Thrum's
> defaults, or "ok" to go on.

<!-- markdownlint-enable MD013 -->

## The two passes

There are two read-only passes: security, with `resources/history-security.md`,
and performance, with `resources/history-performance.md`. Each file holds that
pass's prompt and keyword list.

Before the passes, run git rev-parse --is-shallow-repository. When it prints
true, the result is "not enough to tell" and the reason says this is a shallow
clone, so part of the history is not here. If a pass still makes a finding, it
reports found and the shallow clone is named beside it.

Give each pass to a sub-agent of this runtime when it has one. Otherwise run it
yourself.

Never hand a pass to an outside tool or service.

The result is the same either way, and so is every bound below.

Narrow the history first with git log --grep and the pass's keyword list, over
the newest 2,000 non-merge commits. When there are fewer, read all of them. The
commits searched are those commits, and "fewer than 50 commits" below counts
them. Use the pass's ready-made pattern line exactly as written.

For each matching commit read the subject, the first 20 lines of the body and
the paths it touched. Read nothing else.

## What counts as a finding

An area is a file, or the directory a file sits in. The repository root is never
an area.

A matching commit counts once for every file it touched and once for the
directory each such file sits in.

A finding is an area with at least two different matching commits.

When a file and its directory both qualify, report the file.

For each finding, return the area, one plain sentence on the pattern, and the
supporting commits (short sha and subject).

## The three results

Each pass returns one of three results, as exact strings, and keeps them apart:

- `found`: at least one finding.
- `nothing found`: the history was readable and held no repeated fix of this
  kind.
- `not enough to tell`: the history cannot answer.

Report "not enough to tell" only when the pass made no finding and one of these
holds: there is no git history, the clone is shallow, there are fewer than 50
commits, or most matching messages say too little to classify. Say which.

A pass that made a finding reports `found`, however short the history.

## The result file

Check each commit's text against the inventory's credential patterns before
writing it to the result file. Leave out a commit that matches, and count it.
Apply the same check to any commit text you quote to the owner or pass on, and
when in doubt leave the commit out. Write only the short sha and subject of a
commit, never body lines.

The file `.thrum/results/history-analysis.md` stays on this machine and is not
committed. Run git check-ignore -q on the notes file. If git can see it, tell
the owner and never stage it. It starts with `Read at: <sha>`, then the number
of commits searched and the number that matched, the number left out for
credentials, then each pass's result, its findings, and a `## Dropped` list of
the findings the owner dropped. A re-read is due when the file is absent or
`git rev-list --count <sha>..HEAD` is 100 or more. A re-read keeps the
`## Dropped` list.

When the clone is shallow, the reason in the result file and the sentence you
say to the owner both name the shallow clone, before any commit count.

## Using the findings

Nothing from this analysis reaches a committed file except through a row the
owner accepted.

A dropped finding is recorded and never shown again.

Ask for the findings once, before the first part that uses one, as a block
(`resources/question-blocks.md`): each finding with its commits,
`Recommended: use it`, and the other answer `drop it`.

```text
Block <i> of <k>: What I found in the history

<n>. <area>: <one plain sentence on the pattern>
   Choices: use it / drop it (pick one)
   Recommended: use it
   Why: <short sha and subject of each supporting commit>

Reply "yes to all", tell me what to change (for example "3: weekly"), say "not sure about 3", or ask "explain 3".
```

When a pass found nothing, add a History: line under the fallback Why: line that
gives the pass's result. When the Why: lines are left out because every row is a
fallback, put the History: line under the fallback line.

## What uses the findings

Every part reads its use of the findings from here:

- The security part: the actors block and the proposed watch list.
- The engineering-rules part: the question about mistakes the owner has seen is
  seeded with the repeated-fix patterns.
- The gates and hot-path parts: the performance areas are the recommended hot
  paths, and their commits are the proposed incident notes.
