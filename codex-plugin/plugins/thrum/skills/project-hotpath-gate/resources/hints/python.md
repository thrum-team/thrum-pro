# Python hint

Optional input to `project-hotpath-gate`. The generic wording in the skill is
the base; this file adds Python idioms. Confidence labels on linter rules: High
(stable, documented), Medium (partly verified), Low (from memory, check before
relying).

## Discovery

Manifest signal: `pyproject.toml`, `requirements.txt` or `setup.py`. Use
`--include='*.py'` and exclude tests and virtual environments. Long-running
processes first:

```bash
grep -rnE 'uvicorn|gunicorn|hypercorn|daphne|celery .* worker|dramatiq|rq worker|arq ' Procfile Dockerfile* docker-compose*.y*ml Makefile pyproject.toml
```

Route, handler and worker files, for `trigger_directories`:

```bash
grep -rlE '@(app|bp|router|\w+_router)\.(route|get|post|put|delete|patch|websocket)\(|APIRouter\(|add_url_rule\('
grep -rlE 'Route\(|Mount\(|WebSocketRoute\(|add_middleware\(|class \w+\((HTTPEndpoint|MethodView)\)'
grep -rlE 'class \w+\((\w*View|APIView|ViewSet|ModelViewSet)\)|@api_view|@receiver\(|def process_(request|view)\('
grep -rlE 'web\.RouteTableDef|@routes\.(get|post)|class \w+\(RequestHandler\)|class \w+Servicer\b'
grep -rlE '@(shared_task|\w+\.task)\b|beat_schedule|CELERY_BEAT_SCHEDULE|@dramatiq\.actor|aiokafka|aio_pika|def on_message\('
```

Django hidden hot paths: signal receivers run inside every `.save()`, serializer
methods run per row, and middleware runs per request. Collapse to the parent
directory when it already matches.

The `async_io_decoupling` fields: the shared scarce resource is the event loop
thread, a sync worker slot, or the interpreter lock. Scoped to
`trigger_directories`:

- `io_work_patterns`:
  `subprocess\.|requests\.|urllib\.request|open\(|shutil\.(copy|rmtree|move)|os\.(walk|scandir|listdir)|\.execute\(|\.objects\.|time\.sleep\(`
- `boot_and_coupling_patterns`:
  `lifespan|on_event\(.startup|AppConfig|def ready\(|worker_ready|asyncio\.(gather|wait_for|TaskGroup)`
- `async_discipline_patterns`:
  `asyncio\.timeout|wait_for\(|to_thread\(|run_in_executor|run_in_threadpool|CancelledError|add_done_callback|TaskGroup`
- `dropped_ctx_pattern`: `except (asyncio\.)?CancelledError:\s*pass`, a bare
  `except:` or `except BaseException` inside a coroutine (swallows
  cancellation).

Facts to carry into the context prose: a blocking call inside `async def` stalls
every request on that worker; a plain `def` endpoint in FastAPI or Starlette
runs in a thread pool, so blocking there only exhausts the pool; `requests` has
no default timeout; `httpx` defaults to 5 seconds a phase; `aiohttp` to 300
seconds in total.

## Lenses

- Expensive call in the request path: `subprocess` and a synchronous HTTP client
  inside `async def`.
- Dispatch blocking: a lock held across I/O; CPU work that holds the interpreter
  lock (use a process pool).
- Silent fail-open: bare `except:`, `except Exception: pass`,
  `contextlib.suppress(Exception)`.
- Dual-source write: two writers upsert the same row with no version or
  timestamp guard.
- Per-row cost: a query per item in a loop (Django N+1), a list that includes
  finished or retired items.
- Unbounded outbound calls: no `timeout=`, and no breaker around a service call.
- Unrecovered async failure: `asyncio.create_task(...)` with the task dropped;
  keep a reference and add a done callback.
- Fan-out with no cap: `asyncio.gather(*[...])` over caller input; use a
  semaphore.
- Frozen identity key: `hash()` of a string persisted (it differs per process);
  use `hashlib`.
- Open route: a route on a public router with no `Depends(...)` or
  decorator-level auth, including router-level and settings-level auth defaults.
- Test lens: `assert`-free tests, and tests that only check a mock was called.

## Linter rules

| Rule                                                                                      | Covers                                  | Confidence |
| ----------------------------------------------------------------------------------------- | --------------------------------------- | ---------- |
| ruff `ASYNC210`, `ASYNC221`, `ASYNC230`, `ASYNC251`                                       | blocking calls in `async def`           | High       |
| ruff `S113`, pylint `W3101`, bandit `B113`                                                | HTTP call with no timeout               | High       |
| ruff `RUF006`                                                                             | dangling asyncio task                   | High       |
| ruff `E722`, `BLE001`, `S110`, `S112`, `SIM105`                                           | swallowed exceptions                    | High       |
| ruff `B015`, `B017`, `PT011`                                                              | weak or vacuous test assertions         | High       |
| ruff `S602`-`S607`, bandit `B602`                                                         | subprocess with shell or partial path   | High       |
| ruff `TID251`                                                                             | ban an API per directory (needs config) | High       |
| pylint `W0702`, `W0718`                                                                   | bare or broad except                    | Medium     |
| nplusone, `django_assert_max_num_queries`                                                 | N+1 at runtime or in tests              | High       |
| blockbuster, `PYTHONASYNCIODEBUG=1`                                                       | blocking inside the loop (runtime)      | High       |
| mutmut, cosmic-ray                                                                        | mutation testing for coincidence tests  | Medium     |
| A lock held across I/O, an unguarded upsert, a missing concurrency cap, a secret in a log | no stock rule; reviewer judgment        | Low        |
