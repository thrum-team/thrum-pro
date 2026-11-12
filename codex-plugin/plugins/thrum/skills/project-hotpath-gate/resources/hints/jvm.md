# Java and Kotlin hint

Optional input to `project-hotpath-gate`. The generic wording in the skill is
the base; this file adds JVM idioms. Confidence labels on linter rules: High
(stable, documented), Medium (partly verified), Low (from memory, check before
relying).

## Discovery

Manifest signal: `pom.xml`, `build.gradle`, `build.gradle.kts`,
`settings.gradle(.kts)`. Use `*.java`, `*.kt` and `*.kts`; exclude `src/test`,
`build/`, `target/` and `generated/`. The manifest names the framework:
`spring-boot-starter-web`, `spring-boot-starter-webflux`, `io.ktor`, `quarkus-`,
`micronaut-`, `vertx-`, `spring-kafka`, `grpc-`. Route, handler and consumer
files, for `trigger_directories` (take the parent directory of each match):

```bash
grep -rlE '@(Rest)?Controller\b|@(Get|Post|Put|Delete|Patch|Request)Mapping\b|RouterFunction|coRouter\s*\{'
grep -rlE 'OncePerRequestFilter|WebFilter\b|HandlerInterceptor|GlobalFilter|javax\.servlet\.Filter|jakarta\.servlet\.Filter'
grep -rlE '@Path\(|@Route\(|@ServerFilter|routing\s*\{|router\.(get|post|put|delete|route)\('
grep -rlE '@KafkaListener|KafkaConsumer<|@RabbitListener|@JmsListener|@SqsListener|@Incoming\('
grep -rlE 'ImplBase|CoroutineImplBase|@GrpcService'
grep -rlE '@Scheduled|ScheduledExecutorService|TimerTask|Flux\.interval|@EventListener|@Observes\b'
grep -rlE 'JpaRepository|JdbcTemplate|EntityManager|DSLContext|@Transactional|@PostConstruct|ApplicationRunner|SmartLifecycle'
```

Filters and interceptors run on every request and carry the highest multiplier.
A repo with zero hits across all lines is not a service: ask the owner.

The `async_io_decoupling` fields, scoped to `trigger_directories`:

- `io_work_patterns`:
  `Files\.(walk|list|copy|readAllBytes)|FileInputStream|ProcessBuilder|Runtime\.getRuntime\(\)\.exec|Thread\.sleep|\.block\(\)|runBlocking|JdbcTemplate|restTemplate|HttpURLConnection`
- `boot_and_coupling_patterns`:
  `@PostConstruct|ApplicationRunner|CommandLineRunner|SmartLifecycle|ApplicationReadyEvent|InitializingBean|@DependsOn`
- `async_discipline_patterns`:
  `CompletableFuture\.(supplyAsync|runAsync)|\.exceptionally\(|whenComplete|UncaughtExceptionHandler|CoroutineExceptionHandler|supervisorScope|withTimeout|@Async|boundedElastic|limitedParallelism`
- `dropped_ctx_pattern`: `catch \(InterruptedException[^)]*\) \{\s*\}`
  (swallowed interrupt), `runCatching` around suspend calls, `GlobalScope`, a
  scope created inside a handler and orphaned from the request, and `@Async` or
  `supplyAsync` that loses the security or trace context.

Blocking on an event-loop thread, in order of how often it bites: `runBlocking`,
`.block()` or `Future.get()` inside a reactive handler; file, JDBC or
`RestTemplate` calls on the event loop or the Kafka poll thread; unbounded
executor queues (`Executors.newFixedThreadPool`, `newCachedThreadPool`,
`Channel.UNLIMITED`).

## Lenses

- Expensive call in the request path: `ProcessBuilder`, a blocking client in a
  reactive handler.
- Dispatch blocking: `Thread.sleep` or I/O inside a `synchronized` block or
  while a lock is held.
- Silent fail-open: an empty `catch`, `catch (Exception e) { log }` that carries
  on, `runCatching` that swallows cancellation.
- Dual-source write: two writers persist the same entity with no version column.
- Per-row cost: N+1 lazy loading, a list that includes retired rows.
- Unbounded outbound calls: an HTTP client with no timeout and no breaker
  (Resilience4j is the mitigated form).
- Unrecovered async failure: an uncaught exception kills only that thread, so
  the failure is a silent wedge. `scheduleAtFixedRate` stops forever after one
  exception; `CompletableFuture.runAsync` with no `.exceptionally`;
  `GlobalScope.launch`; `.subscribe()` with no error consumer; a Kafka poison
  record with no error handler.
- Fan-out with no cap: unbounded `flatMap`, `async` over caller input.
- Open route: a controller with security disabled or CSRF turned off for a
  public route.

## Linter rules

| Rule                                                                        | Covers                                              | Confidence |
| --------------------------------------------------------------------------- | --------------------------------------------------- | ---------- |
| BlockHound                                                                  | blocking call on a non-blocking thread (runtime)    | High       |
| detekt `GlobalCoroutineUsage`                                               | `GlobalScope`                                       | High       |
| detekt `SwallowedException`, `EmptyCatchBlock`, `TooGenericExceptionCaught` | silent fail-open                                    | High       |
| Error Prone `FutureReturnValueIgnored`, `EmptyCatch`                        | dropped future, empty catch                         | High       |
| SpotBugs `SWL_SLEEP_WITH_LOCK_HELD`                                         | sleep under a lock                                  | High       |
| SonarJava `S4502`                                                           | CSRF disabled                                       | High       |
| SonarJava `S2276`, `S2699`                                                  | sleep under lock, test with no assertion            | Medium     |
| CodeQL `java/sensitive-log`                                                 | secret in a log                                     | High       |
| detekt `SuspendFunSwallowedCancellation`                                    | swallowed cancellation (off by default)             | Medium     |
| PMD `EmptyCatchBlock`, `AvoidCatchingThrowable`                             | broad or empty catch                                | Medium     |
| ArchUnit                                                                    | forbidden dependencies, reference-pattern tripwires | Medium     |
| datasource-proxy `SQLStatementCountValidator`                               | N+1 in tests                                        | High       |
| PIT mutation testing                                                        | tests that pass when broken                         | Medium     |
| Dual-source writes, missing timeouts and breakers, unbounded `flatMap`      | no stock rule; reviewer judgment                    | Low        |
