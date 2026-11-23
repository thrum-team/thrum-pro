# Implementation Philosophy

> **For all agents:** This document governs how features are built. Read this
> BEFORE any plan file or task descriptions. When in doubt, ask: "[your >
> project's guiding question — e.g., 'Am I using the real thing, or faking >
> it?']"
>
> **Fill this template** for your project. The pre-filled examples below are
> universal defaults — adapt, replace, or extend them for your domain.

## Core Principle

**Every implementation MUST satisfy ALL of these criteria:**

1. [Criterion 1 — e.g., The code calls the real component that owns the
   behaviour, not hardcoded data]
2. [Criterion 2 — e.g., Output is built from the real response, not text written
   by hand into the code]
3. [Criterion 3 — e.g., Changing the underlying data changes the output]
4. [Criterion 4 — e.g., Access control uses real permission checks made where
   the data is held, not checks in the caller's display layer]
5. The verification step in the task description passes

## Decision Framework

When implementing any requirement, follow this decision tree:

| Question                                       | Action                                                |
| ---------------------------------------------- | ----------------------------------------------------- |
| Does a component that does this already exist? | Use it. Do not rewrite.                               |
| Does it exist but need extension?              | Extend it, then use it.                               |
| Is this purely new capability?                 | Build the minimal component first, then what uses it. |
| Is this seed data / configuration?             | Load into the real store, not hardcoded.              |

## Anti-Patterns

<!-- Define BAD/GOOD code examples. Sections 1-3 are universal defaults.  -->
<!-- Sections 4+ are seeded from the reliability-class-library probe     -->
<!-- (project-philosophy SKILL.md Step 4a) — as many numbered sections as the probe finds, not a fixed count. -->
<!-- The BAD/GOOD format is critical — it makes the standard concrete and unambiguous. -->

### 1. Hardcoded data where real data belongs

```text
// BAD — the function returns a fixed list and ignores the data layer
function listItems():
    return [{name: "hardcoded-1"}, {name: "hardcoded-2"}]

// GOOD — it asks the data layer for the real list and reports failures
function listItems():
    items, error = store.listItems()
    if error: report the error and stop
    return items
```

**Why:** Hardcoded data passes tests but breaks when real data changes. It
creates a false sense of completion.

### 2. Hiding instead of denying

```text
// BAD — everything is sent, and the caller's display hides what the user
// may not use
send all actions to the caller
caller hides the actions the user may not use

// GOOD — the owner of the data returns only what this user may use, and
// refuses any other request
send only the actions this user may use
refuse a request for any other action
```

**Why:** Hiding is not access control. The part that holds the data still serves
unauthorized requests.

### 3. Scripted/mocked responses in production paths

```text
// BAD — the function returns a pre-written answer instead of calling the
// real service
function analyze(request):
    return {result: "This ticket appears to be high priority..."}

// GOOD — it calls the real analysis service
function analyze(request):
    result = analysisService.analyze(request.ticketId)
    return {result: result}
```

**Why:** Scripted responses mask integration failures. The service may not
actually work, and you won't know until production.

### 4. [Project-specific anti-pattern]

```text
// BAD
// GOOD
```

**Why:** [Impact explanation]

### 5. [Project-specific anti-pattern]

```text
// BAD
// GOOD
```

**Why:** [Impact explanation]

## Acceptable Simplifications

Not everything needs to be production-grade. These simplifications are OK:

| Simplification                  | Why It's OK                          | Boundary (when to stop)                |
| ------------------------------- | ------------------------------------ | -------------------------------------- |
| Lightweight dependency stand-in | Same interface, simpler setup        | When behaviour under real load matters |
| Cached/mock external APIs       | Deterministic tests, no network deps | When testing real API behavior changes |
| Static seed data                | Reproducible demos and tests         | When data must reflect real user input |
| [Project-specific]              | [Rationale]                          | [Boundary]                             |

## Red Flags

If you see any of these in your code, **STOP and fix before continuing:**

- [ ] Literal data returned instead of coming from the real store or service
- [ ] Output assembled by hand in code (string concatenation) where the project
      has a template or formatter
- [ ] Missing error handling on service/store calls
- [ ] TODO/FIXME comments left in committed code
- [ ] [Project-specific red flag]
- [ ] [Project-specific red flag]
- [ ] [Project-specific red flag]

## For Implementation Agents

### Before You Start a Task

- [ ] Read the design doc referenced in your prompt
- [ ] Read the task description (the show command of the configured tracker,
      given the task id) — it's your source of truth
- [ ] Search the plan file for your task's implementation code
      (`grep "## Task: {BEAD_ID}" plan-file.md`)
- [ ] Identify which existing components to use (do not reimplement)
- [ ] Review the anti-patterns above — know what NOT to do

### Before You Close a Task

- [ ] All acceptance criteria in the task are satisfied
- [ ] Tests pass (run quality commands from your prompt)
- [ ] No red flags present in your implementation
- [ ] Commit message is descriptive
- [ ] Code follows existing project patterns and conventions
