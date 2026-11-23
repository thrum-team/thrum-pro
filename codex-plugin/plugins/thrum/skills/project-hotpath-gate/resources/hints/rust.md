# Rust hint

Optional input to `project-hotpath-gate`. The generic wording in the skill is
the base; this file adds Rust idioms. Confidence labels on linter rules: High
(stable, documented), Medium (partly verified), Low (from memory, check before
relying).

## Discovery

Manifest signal: `Cargo.toml` (read `[workspace] members` in the root). Find
service crates first, then use their directories as `trigger_directories`:

```bash
grep -rlE '^(axum|actix-web|tonic|rocket|warp|poem|hyper|tower)\s*=' --include=Cargo.toml .
```

Binary crates are `src/main.rs` and `src/bin/*.rs`; `*.proto` files and a
`build.rs` calling `tonic_build` mark gRPC crates. Route, handler and worker
files (`--include='*.rs'`):

```bash
grep -rlE 'Router::new\(\)|\.route\(\s*"|\.nest\(|axum::extract|#\[debug_handler\]'
grep -rlE '#\[(get|post|put|delete|patch)\(|web::(resource|scope)\(|HttpServer::new|#\[handler\]|warp::(path|get|post)'
grep -rlE 'service_fn\(|Service<|Layer<|#\[tonic::async_trait\]|add_service\(|Server::builder\(\)'
grep -rlE 'while let Some\(.*\) = .*\.(recv|next)\(\)\.await|\.tick\(\)\.await|tokio::spawn\(|JoinSet'
grep -rlE 'StreamConsumer|lapin::|async_nats|PgListener|aws_sdk_sqs|apalis|tokio_cron_scheduler'
grep -rlE 'sqlx::|diesel::|sea_orm::|rusqlite::|tokio_postgres::|OpenOptions|tokio::fs'
```

Handlers are plain functions registered by value, so read the router
registration list to find them:
`grep -rnE '(get|post|put|delete|patch|any)\(\s*\w+(::\w+)*\s*\)'`. Conventional
directories: `src/routes/`, `src/handlers/`, `src/api/`, `src/services/`,
`src/workers/`, `src/consumers/`, `src/jobs/`. Control: a repo with `axum` in
`Cargo.toml` must match `Router::new` at least once; zero hits means the grep
was scoped wrong.

The `async_io_decoupling` fields. The executor has few worker threads (default:
the core count), so blocking work or a held lock stalls unrelated tasks, and a
future can be dropped at any `.await`. Scoped to `trigger_directories`:

- `io_work_patterns`, inside `async fn` or `async {`:
  `std::fs::|std::process::Command|std::thread::sleep|reqwest::blocking|std::net::TcpStream|std::io::copy|walkdir::|rusqlite::`.
  Also nested runtimes:
  `block_on\(|Handle::current\(\)\.block_on|block_in_place`.
- `boot_and_coupling_patterns`:
  `tokio::join!|try_join!|select!|JoinSet|OnceCell|Notify|watch::channel|Barrier|oneshot::channel`,
  in `main` or boot code.
- `async_discipline_patterns`:
  `CancellationToken|cancelled\(\)|tokio::time::timeout|spawn_blocking|JoinHandle::abort|kill_on_drop|Semaphore`.
- `dropped_ctx_pattern`: functions that do I/O and take no `CancellationToken`
  or deadline; parameters named `_token`, `_cancel` or `_ct`;
  `let _ = tx.send(`; `.abort()` with no cleanup await. Also check `select!`
  arms holding `read_exact`, `read_line`, `read_to_end` or `write_all`: a
  dropped future loses partial progress.

## Lenses

- Expensive call in the request path: `std::process::Command`, a raw fork-class
  OS call.
- Dispatch blocking: blocking calls in a task (move to `tokio::fs`,
  `tokio::process` or `spawn_blocking`); a lock guard held across `.await`.
- Silent fail-open: `let _ = call();`, `.ok()` that drops an error,
  `unwrap_or_default()` over a failure.
- Dual-source write: two writers upsert the same row with no version guard.
- Per-row cost: an `.await` per item in a loop, a list that includes retired
  rows.
- Unbounded outbound calls: an async `reqwest` client has no default timeout; no
  breaker.
- Unrecovered async failure: a panic in a spawned task is held in the
  `JoinHandle` and lost if nobody awaits it.
- Fan-out with no cap: `join_all` or a spawn per item over caller input; use a
  `Semaphore` or `ConcurrencyLimitLayer`.
- Frozen identity key: `DefaultHasher` output persisted.
- Open route: a router with no auth layer on a public path.
- Secret in a log: `#[instrument]` on a function with a token parameter, with no
  `skip(...)`.

## Linter rules

| Rule                                                                                      | Covers                                             | Confidence |
| ----------------------------------------------------------------------------------------- | -------------------------------------------------- | ---------- |
| `clippy::await_holding_lock`                                                              | lock guard held across `.await`                    | High       |
| `clippy::await_holding_refcell_ref`                                                       | `RefCell` borrow across `.await`                   | High       |
| `clippy::disallowed_methods`, `disallowed_types`                                          | ban a pattern per project (set in `clippy.toml`)   | High       |
| `clippy::let_underscore_must_use`, `let_underscore_future`                                | ignored results and futures                        | High       |
| `clippy::unwrap_used`, `expect_used`                                                      | panics on failure (opt-in)                         | High       |
| `clippy::large_futures`, `future_not_send`, `unused_async`                                | async hygiene                                      | High       |
| `clippy::print_stdout`, `dbg_macro`                                                       | stray output                                       | High       |
| rustc `unused_must_use`                                                                   | dropped `Result` or future                         | High       |
| cargo-mutants                                                                             | tests that pass when broken                        | High       |
| tokio-console                                                                             | slow task polls (runtime; needs `tokio_unstable`)  | Medium     |
| tower `TimeoutLayer`, `ConcurrencyLimitLayer`, `LoadShedLayer`                            | mitigated form of timeout and cap                  | Medium     |
| `clippy::await_holding_invalid_type`                                                      | configurable held-type check (spelling unverified) | Low        |
| An unguarded upsert, a missing breaker, a persisted `DefaultHasher`, a missing auth layer | no stock rule; reviewer judgment                   | Low        |
