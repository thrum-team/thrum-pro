# Go hint

Optional input to `project-hotpath-gate`. The generic wording in the skill is
the base; this file adds Go idioms. Confidence labels on linter rules: High
(stable, documented), Medium (partly verified), Low (from memory, check before
relying).

## Discovery

Route, handler and RPC files, for `trigger_directories`:

```bash
grep -rlE 'func Handle|func.*Handler|http\.Handle|rpc\.' --include='*.go'
```

Manifest signal: `go.mod`. Skip `_test.go` files and `vendor/`.

The `async_io_decoupling` primary fields come from this Go-only pass,
independent of the class library, scoped to `trigger_directories`:

```bash
grep -rnE 'go func|go bootstage\.Run' --include='*.go'
grep -rnE 'bootstage\.Run|OnReady|SetOnReady|DependsOn|Await\(' --include='*.go'
grep -rnE 'CompactAll|MergeGroup|filepath\.Walk|os\.ReadDir|io\.Copy' --include='*.go'
grep -rnE 'ctx\.Done\(\)|ctx\.Err\(\)|r\.Beat\(|context\.WithoutCancel' --include='*.go'
grep -rn '_ context\.Context' --include='*.go'
```

Record them as `io_work_patterns`, `boot_and_coupling_patterns`,
`async_discipline_patterns` and `dropped_ctx_pattern`, in that order. The
boot-stage names in the second and third lines come from one project: replace
them with the repo's own names when its boot code uses a different helper.

Pass the reliability-class library's Go probe for each hot-path class. Where the
library gives no Go probe (Classes 16, 17 and 18 for a perimeter-protected
daemon), that class adds nothing for Go.

`embed_aware_skip` applies to Go: a `//go:embed` directive marks a compiled-in
bundle, and the reachability command is `go list -deps` on the entrypoint.

## Lenses

- Dispatch blocking: one goroutine that serves every request or message and
  calls slow work inline, or a mutex held across a network, exec or disk call.
  Look for `.Lock()` followed by such a call.
- Subprocess: `exec.Command` and `exec.CommandContext` reachable from a handler.
- Silent fail-open: `if err != nil { return nil }` and an ignored `_ = call()`
  on a privileged path.
- Dual-source write: `INSERT OR REPLACE` and `INSERT OR IGNORE` where two
  sources write the same row.
- Shared-resource poisoning: a helper that opens the main database read-write
  when read-only would do.
- Dead-row pre-filter: a loop that does per-row work after a weak liveness
  check.
- Network calls: an `http.Client` with no `Timeout`, a dial with no context
  deadline, and no breaker.
- Unrecovered async failure: `go func()` with no `recover()` kills the whole
  process on a panic.

## Linter rules

| Rule                                                               | Covers                                             | Confidence |
| ------------------------------------------------------------------ | -------------------------------------------------- | ---------- |
| `go vet` (copylocks, lostcancel)                                   | locks copied by value, leaked cancel funcs         | High       |
| staticcheck SA1015, SA2002                                         | ticker leaks, `t.Fatal` outside the test goroutine | High       |
| staticcheck SA5001, SA9003                                         | deferred close before error check, empty branch    | High       |
| errcheck                                                           | ignored error returns (silent fail-open)           | High       |
| gosec G204                                                         | subprocess started with variable input             | High       |
| gosec G104                                                         | unhandled error                                    | Medium     |
| noctx                                                              | HTTP request built without a context               | High       |
| bodyclose                                                          | response body never closed                         | High       |
| contextcheck                                                       | context dropped between calls                      | Medium     |
| forbidigo, depguard                                                | ban a legacy pattern in chosen directories         | Medium     |
| revive `unused-parameter`                                          | dropped context parameter                          | Medium     |
| goleak (test library)                                              | goroutine leaks in tests                           | Medium     |
| A lock held across I/O, an unguarded upsert, a frozen identity key | no stock rule; reviewer judgment                   | Low        |
