# C# and .NET hint

Optional input to `project-hotpath-gate`. The generic wording in the skill is
the base; this file adds C# idioms. Confidence labels on linter rules: High
(stable, documented), Medium (partly verified), Low (from memory, check before
relying).

## Discovery

Manifest signal: `*.csproj`, `*.sln`, `*.slnx`, `Directory.Build.props`. The
project SDK names the host type: `Microsoft.NET.Sdk.Web` is a web host,
`Microsoft.NET.Sdk.Worker` a worker. Use `--include='*.cs'` and exclude
`*.Tests`, `Migrations/`, `obj/`, `bin/`, `*.g.cs` and `*.Designer.cs`. Route,
handler and consumer files, for `trigger_directories`:

```bash
grep -rlE ':\s*(Controller|ControllerBase)\b|\[ApiController\]|\[Http(Get|Post|Put|Delete|Patch)'
grep -rlE '\.Map(Get|Post|Put|Delete|Patch|Methods|Group)\(|MapControllers\(|MapHub<|MapGrpcService<'
grep -rlE ':\s*\w+\.\w+Base\b|\[GrpcService\]|:\s*Hub(<[^>]+>)?\b'
grep -rlE ':\s*(BackgroundService|IHostedService|IHostedLifecycleService)\b|ExecuteAsync\('
grep -rlE 'IConsumer<|IRequestHandler<|INotificationHandler<|ServiceBusProcessor|BasicConsume|EventingBasicConsumer'
grep -rlE 'IMiddleware|InvokeAsync\(HttpContext|IActionFilter|IAsyncActionFilter|IEndpointFilter|DelegatingHandler'
grep -rlE ':\s*DbContext\b|DbSet<|SqlConnection|NpgsqlConnection|SaveChangesAsync|ExecuteSqlRaw'
```

Directories named `Controllers/`, `Endpoints/`, `Hubs/`, `Handlers/`,
`Consumers/`, `Workers/`, `Middleware/` and `Features/` are signals too.
Collapse to the project directory. The scarce shared resource is the thread
pool, plus the database connection pool; a hot path is a request or message
thread and the pool it draws from.

The `async_io_decoupling` fields, scoped to `trigger_directories`:

- `io_work_patterns`:
  `\.Result\b|\.Wait\(|\.WaitAll\(|GetAwaiter\(\)\.GetResult\(|Thread\.Sleep\(|File\.(ReadAll|WriteAll)\w*\(|\.ReadToEnd\(\)`
- `boot_and_coupling_patterns`:
  `:\s*BackgroundService|IHostedService|IHostedLifecycleService|ApplicationStarted|AddHealthChecks`.
  Record the `<TargetFramework>` too: .NET 10 changes whether slow startup work
  blocks the host.
- `async_discipline_patterns`:
  `stoppingToken|ThrowIfCancellationRequested|IsCancellationRequested|WithCancellation\(|CancelAfter\(|async\s+void|Task\.Run\(`
- `dropped_ctx_pattern`:
  `CancellationToken\s+\w+\s*=\s*default|CancellationToken\.None|default\(CancellationToken\)`.
  An explicit `CancellationToken.None` is an opt-out the analyzers do not flag,
  so grep it.

## Lenses

- Expensive call in the request path: `Process.Start`, `new HttpClient()` per
  request, synchronous file reads.
- Dispatch blocking: sync-over-async (`.Result`, `.Wait()`) starves the thread
  pool; a lock held across an await.
- Silent fail-open: `catch (Exception) { }`, a catch that returns a default.
- Dual-source write: two writers call `SaveChangesAsync` on the same row with no
  concurrency token.
- Per-row cost: a query inside a loop, a list that includes retired items.
- Unbounded outbound calls: `HttpClient` default timeout is 100 seconds, with no
  per-call token and no breaker (Polly or `Microsoft.Extensions.Http.Resilience`
  is the mitigated form).
- Unrecovered async failure: `async void`, `Task.Run` fire-and-forget,
  `_ = FooAsync()`.
- Fan-out with no cap: `Task.WhenAll` over caller input.
- Open route: a controller or endpoint with no `[Authorize]` and no fallback
  policy.

## Linter rules

| Rule                                                                                 | Covers                                             | Confidence |
| ------------------------------------------------------------------------------------ | -------------------------------------------------- | ---------- |
| `CA2016`                                                                             | cancellation token not forwarded                   | High       |
| `CA1849`                                                                             | blocking call inside async method (off by default) | High       |
| `CA1031`                                                                             | general catch clause                               | High       |
| `VSTHRD002`, `VSTHRD103`                                                             | sync wait on a task, blocking call in async        | High       |
| `VSTHRD100`, `VSTHRD110`                                                             | `async void`, task not awaited                     | High       |
| `CS4014`                                                                             | call not awaited                                   | High       |
| `AsyncFixer01`, `AsyncFixer02`, `AsyncFixer03`                                       | blocking, async void                               | High       |
| Meziantou `MA0042`, `MA0040`, `MA0004`                                               | blocking, token, ConfigureAwait                    | High       |
| `RS0030` (BannedApiAnalyzers)                                                        | ban `Process.Start`, `new HttpClient()`, `.Result` | High       |
| Sonar `S3168`, `S4462`, `S2699`                                                      | async void, blocking, tests with no assertion      | High       |
| `CA2007`                                                                             | ConfigureAwait in library code                     | Medium     |
| Stryker.NET                                                                          | mutation testing for coincidence tests             | High       |
| I/O under a lock, a missing auth attribute, N+1, unguarded writes, a missing breaker | no stock rule; reviewer judgment                   | Low        |
