# JavaScript and TypeScript hint

Optional input to `project-hotpath-gate`. The generic wording in the skill is the base; this file adds JS and TS
idioms. Confidence labels on linter rules: High (stable, documented), Medium (partly verified), Low (from memory,
check before relying).

## Discovery

Manifest signal: `package.json` (and `tsconfig.json` for TypeScript). Read `workspaces` in the root manifest,
`pnpm-workspace.yaml`, `turbo.json` and `nx.json`; a directory with `express`, `fastify`, `@nestjs/*` or `next` in
`dependencies` is a hot-path candidate. Use these globs for every grep below and exclude `node_modules`, `dist`,
`build`, `*.test.*`, `*.spec.*` and `__tests__`:

```bash
--include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.cjs'
```

Route, handler and consumer files, for `trigger_directories`:

```bash
grep -rlE '\b(app|router|api)\.(get|post|put|patch|delete|all|use)\(|express\.Router\(\)'
grep -rlE '\b(fastify|app|server)\.(get|post|put|patch|delete|route|addHook)\('
grep -rlE '@(Controller|Get|Post|MessagePattern|EventPattern|SubscribeMessage|Processor|Cron)\('
grep -rlE 'export (async )?function (loader|action)\b|export (const|async function) handler|exports\.handler'
grep -rlE '\.(query|mutation|subscription)\(|publicProcedure|protectedProcedure|new ApolloServer|createYoga'
grep -rlE 'new (Worker|QueueEvents)\(|consumer\.run\(|channel\.consume\(|new WebSocketServer\(|io\.on\(.connection'
grep -rlE 'http2?\.createServer\(|setInterval\(|new CronJob\(|cron\.schedule\('
```

File conventions: `app/**/route.ts`, `pages/api/**`, `middleware.ts`, `+server.ts`, `server/api/**`. Storage and
sync directories: files importing `pg`, `mysql2`, `mongoose`, `@prisma/client`, `typeorm`, `knex`, `drizzle-orm`,
`better-sqlite3`, `ioredis` or `redis`. For a front end, add `src/components`, `src/hooks` and list or table
components that re-render often.

The `async_io_decoupling` fields come from the event-loop idiom, scoped to `trigger_directories`:

- `io_work_patterns`:
  `\b(fs|fsSync)\.\w+Sync\(|\b(execSync|spawnSync|execFileSync)\(|\b(pbkdf2|scrypt|gzip|gunzip|deflate|inflate|brotliCompress)Sync\(|bcrypt\.(hash|compare)Sync|readdirSync|JSON\.(parse|stringify)\(`
- `boot_and_coupling_patterns`: `\.listen\(|await .*\.connect\(|process\.on\(.(SIGTERM|SIGINT)|onModuleInit|beforeExit`
- `async_discipline_patterns`:
  `\.catch\(|try\s*\{|process\.on\(|AbortController|AbortSignal\.(timeout|any)|new Worker\(|piscina|workerpool`
- `dropped_ctx_pattern`: an `async` function that takes `signal`, `AbortSignal` or `ctx` and never forwards it to
  `fetch` or a database call. No stock grep; read the function body.

## Lenses

- Expensive call in the request path: synchronous file, crypto or child-process calls, and a large `JSON.parse`.
- Dispatch blocking: a lock helper (`runExclusive`, `withLock`, a mutex) or a database transaction held across an
  HTTP call, such as `prisma.$transaction(async tx => { await fetch(...) })`.
- Silent fail-open: `catch {}`, `.catch(() => {})`, and `?? []` hiding an error state.
- Dual-source write: an API and a webhook (or an optimistic update and a socket push) write the same key with no
  version check.
- Unbounded outbound calls: `fetch` with no `signal`; axios `timeout` defaults to none; a database client with no
  connection timeout. Good form: `AbortSignal.timeout(ms)`.
- Unrecovered async failure: an unawaited promise or a `.then(x)` with no catch ends the process on Node 15 or later.
- Fan-out with no cap: `Promise.all(items.map(...))` over caller-supplied input.
- Browser: heavy work in render or in scroll, resize and pointer handlers; a `fetch` in `useEffect` with no
  `AbortController`; a list rendered with no virtualization.

## Linter rules

| Rule | Covers | Confidence |
|---|---|---|
| `@typescript-eslint/no-floating-promises` | unawaited promises | High |
| `@typescript-eslint/no-misused-promises` | async callback where void is expected | High |
| `promise/catch-or-return` | promise with no catch | High |
| `n/no-sync` | synchronous fs, crypto, child_process (not in recommended) | High |
| `n/no-process-exit` | exit inside request code | High |
| `no-empty` | empty catch block | High |
| `no-await-in-loop` | per-row await (N+1 shape) | High |
| `security/detect-child-process`, `security/detect-unsafe-regex` | subprocess, ReDoS | High |
| `jest/expect-expect`, `vitest/expect-expect` | tests with no assertion | High |
| `react-hooks/exhaustive-deps` | stale effect dependencies | High |
| `no-restricted-imports`, `no-restricted-syntax` | ban a legacy pattern | High |
| `require-atomic-updates` | await races (false positives) | Medium |
| `sonarjs/os-command` | subprocess with variable input | Medium |
| StrykerJS | mutation testing for assertion-free tests | Medium |
| A fetch with no timeout, a lock held across an await, an unguarded upsert, unbounded `Promise.all` | no stock rule; reviewer judgment | Low |
