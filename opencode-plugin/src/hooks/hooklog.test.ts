// Tests for the hooklog capture shim (hooklog.ts) and the composed tool hooks
// (tool-hooks.ts). The shim turns an OpenCode tool-call envelope into the
// Claude-shaped payload `thrum hooklog capture` reads on stdin.
//
// Run: npm test  (builds, then `node --test dist`)

import { test } from "node:test"
import assert from "node:assert/strict"
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { hooklogHooks } from "./hooklog.js"
import { toolHooks } from "./tool-hooks.js"

// Built at runtime so no secret-shaped literal ships in the plugin tree.
const FAKE_SECRET = ["ghp", "FAKE".repeat(9) + "0000"].join("_")

const yes = () => true

type Call = { payload: string; cwd: string }

function recorder() {
  const calls: Call[] = []
  const run = async (payload: string, cwd: string) => {
    calls.push({ payload, cwd })
  }
  return { calls, run }
}

const beforeIn = { tool: "bash", sessionID: "ses_1", callID: "call_1" }
const beforeOut = { args: { command: "ls -la" } }
const afterIn = { tool: "bash", sessionID: "ses_1", callID: "call_1", args: { command: "ls -la" } }
const afterOut = { title: "ls", output: "total 0", metadata: { exit: 0 } }

test("before builds the exact PreToolUse payload and runs in the worktree", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/dir", worktree: "/wt" }, { run, hasThrumDir: yes })
  await h.before(beforeIn, beforeOut)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].cwd, "/wt")
  assert.deepEqual(JSON.parse(calls[0].payload), {
    hook_event_name: "PreToolUse",
    tool_name: "bash",
    tool_use_id: "call_1",
    session_id: "ses_1",
    cwd: "/wt",
    tool_input: { command: "ls -la" },
  })
})

test("after builds the exact PostToolUse payload with tool_response title+output+exit only (no other metadata)", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/dir", worktree: "/wt" }, { run, hasThrumDir: yes })
  await h.after(afterIn, afterOut)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].cwd, "/wt")
  assert.deepEqual(JSON.parse(calls[0].payload), {
    hook_event_name: "PostToolUse",
    tool_name: "bash",
    tool_use_id: "call_1",
    session_id: "ses_1",
    cwd: "/wt",
    tool_input: { command: "ls -la" },
    tool_response: { title: "ls", output: "total 0", exit: 0 },
  })
})

test("worktree falls back to directory when empty or undefined", async () => {
  for (const worktree of ["", undefined]) {
    const { calls, run } = recorder()
    const h = hooklogHooks({ directory: "/dir", worktree }, { run, hasThrumDir: yes })
    await h.before(beforeIn, beforeOut)
    await h.after(afterIn, afterOut)
    assert.equal(calls.length, 2)
    for (const c of calls) {
      assert.equal(c.cwd, "/dir")
      assert.equal(JSON.parse(c.payload).cwd, "/dir")
    }
  }
})

test("worktree \"/\" (non-git dir) falls back to directory", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/dir", worktree: "/" }, { run, hasThrumDir: yes })
  await h.before(beforeIn, beforeOut)
  await h.after(afterIn, afterOut)
  assert.equal(calls.length, 2)
  for (const c of calls) {
    assert.equal(c.cwd, "/dir")
    assert.equal(JSON.parse(c.payload).cwd, "/dir")
  }
})

test("a real worktree path other than \"/\" is still preferred", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/dir", worktree: "/wt/x" }, { run, hasThrumDir: yes })
  await h.before(beforeIn, beforeOut)
  assert.equal(calls[0].cwd, "/wt/x")
})

test("pre and post share tool_use_id so detect pairs them", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/dir" }, { run, hasThrumDir: yes })
  await h.before(beforeIn, beforeOut)
  await h.after(afterIn, afterOut)
  const [pre, post] = calls.map((c) => JSON.parse(c.payload))
  assert.equal(pre.tool_use_id, post.tool_use_id)
  assert.notEqual(pre.hook_event_name, post.hook_event_name)
})

test("a runner that throws or rejects never makes before/after reject", async () => {
  const throwing = hooklogHooks({ directory: "/d" }, { run: (() => { throw new Error("boom") }) as never, hasThrumDir: yes })
  const rejecting = hooklogHooks({ directory: "/d" }, { run: async () => { throw new Error("nope") }, hasThrumDir: yes })
  for (const h of [throwing, rejecting]) {
    await assert.doesNotReject(() => h.before(beforeIn, beforeOut))
    await assert.doesNotReject(() => h.after(afterIn, afterOut))
  }
})

test("malformed input does not throw and omits undefined keys", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  await assert.doesNotReject(() => h.before(undefined as never, undefined as never))
  await assert.doesNotReject(() => h.after(undefined as never, undefined as never))
  await assert.doesNotReject(() => h.before({} as never, {} as never))
  await assert.doesNotReject(() => h.after({ tool: "read" } as never, {} as never))
  // Missing fields must be omitted, not serialised as null.
  const missing = calls.map((c) => JSON.parse(c.payload))
  assert.ok(missing.length > 0, "malformed input still produces a capture attempt")
  for (const p of missing) {
    for (const v of Object.values(p)) assert.notEqual(v, null)
  }
  const last = missing[missing.length - 1]
  assert.equal(last.tool_name, "read")
  assert.equal("session_id" in last, false)
  assert.equal("tool_use_id" in last, false)
  assert.deepEqual(last.tool_input, {})
})

test("a circular tool_input does not throw", async () => {
  const { run } = recorder()
  const h = hooklogHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  const args: Record<string, unknown> = {}
  args.self = args
  await assert.doesNotReject(() => h.before(beforeIn, { args }))
  await assert.doesNotReject(() => h.after({ ...afterIn, args }, afterOut))
})

// --- default runner against a fake `thrum` on PATH ---------------------------

function fakeThrum(script: string, opts: { thrumDir?: boolean } = {}) {
  const root = mkdtempSync(join(tmpdir(), "hooklog-fake-"))
  const bin = join(root, "bin")
  mkdirSync(bin)
  const rec = join(root, "rec")
  mkdirSync(rec)
  writeFileSync(join(bin, "thrum"), `#!/bin/sh\n${script.replaceAll("$REC", rec)}\n`)
  chmodSync(join(bin, "thrum"), 0o755)
  const wt = join(root, "wt")
  mkdirSync(wt)
  if (opts.thrumDir !== false) mkdirSync(join(root, ".thrum"))
  return { root, bin, rec, wt }
}

async function withPath<T>(bin: string, fn: () => Promise<T>): Promise<T> {
  const saved = process.env.PATH
  process.env.PATH = `${bin}:${saved ?? ""}`
  try {
    return await fn()
  } finally {
    process.env.PATH = saved
  }
}

const RECORD = `echo "$@" > $REC/argv; pwd > $REC/cwd; cat > $REC/stdin`

test("default runner invokes `thrum hooklog capture` in the worktree with the payload on stdin", async () => {
  const f = fakeThrum(RECORD)
  const h = hooklogHooks({ directory: "/nonexistent-dir", worktree: f.wt })
  await withPath(f.bin, () => h.before(beforeIn, beforeOut))
  assert.equal(readFileSync(join(f.rec, "argv"), "utf8").trim(), "hooklog capture")
  assert.equal(realpathSync(readFileSync(join(f.rec, "cwd"), "utf8").trim()), realpathSync(f.wt))
  const payload = JSON.parse(readFileSync(join(f.rec, "stdin"), "utf8"))
  assert.equal(payload.hook_event_name, "PreToolUse")
  assert.equal(payload.tool_use_id, "call_1")
  assert.equal(payload.cwd, f.wt)
  assert.deepEqual(payload.tool_input, { command: "ls -la" })
})

test("default runner writes the PostToolUse payload on stdin", async () => {
  const f = fakeThrum(RECORD)
  const h = hooklogHooks({ directory: f.wt })
  await withPath(f.bin, () => h.after(afterIn, afterOut))
  const payload = JSON.parse(readFileSync(join(f.rec, "stdin"), "utf8"))
  assert.equal(payload.hook_event_name, "PostToolUse")
  assert.deepEqual(payload.tool_response, { title: "ls", output: "total 0", exit: 0 })
})

test("a fake thrum that exits 2 leaves before/after resolved", async () => {
  const f = fakeThrum(`cat > $REC/stdin; echo noise; exit 2`)
  const h = hooklogHooks({ directory: f.wt })
  await withPath(f.bin, async () => {
    await assert.doesNotReject(() => h.before(beforeIn, beforeOut))
    await assert.doesNotReject(() => h.after(afterIn, afterOut))
  })
  // Control: the fake did run (it recorded stdin), so the exit-2 path was exercised.
  assert.equal(existsSync(join(f.rec, "stdin")), true)
})

test("a fake thrum that sleeps past the timeout leaves before/after resolved promptly", async () => {
  const f = fakeThrum(`cat > $REC/stdin; exec sleep 5`)
  const h = hooklogHooks({ directory: f.wt }, { timeoutMs: 200 })
  const start = Date.now()
  await withPath(f.bin, async () => {
    await assert.doesNotReject(() => h.before(beforeIn, beforeOut))
  })
  assert.ok(Date.now() - start < 3000, `took ${Date.now() - start}ms, expected the 200ms timeout to bound it`)
  assert.equal(existsSync(join(f.rec, "stdin")), true)
})

test("a missing thrum binary leaves before/after resolved", async () => {
  const empty = mkdtempSync(join(tmpdir(), "hooklog-empty-"))
  mkdirSync(join(empty, ".thrum"))
  const h = hooklogHooks({ directory: empty })
  const saved = process.env.PATH
  process.env.PATH = empty
  try {
    await assert.doesNotReject(() => h.before(beforeIn, beforeOut))
    await assert.doesNotReject(() => h.after(afterIn, afterOut))
  } finally {
    process.env.PATH = saved
  }
})

// --- exit signal from real OpenCode 1.18.35 payloads ---------------------------
// A failing bash call still fires tool.execute.after normally; output.metadata.exit
// is the only failure signal. Shapes below are sanitized copies of measured payloads.

const failingBash = {
  input: {
    tool: "bash",
    sessionID: "ses_e6b7b9839ffeKUP5fNHsdiEPPU",
    callID: "call_bf25ba0479c0440d86ec19fd",
    args: { command: "ls /nonexistent-hookpayload-test", workdir: "~/wt" },
  },
  output: {
    title: "ls /nonexistent-hookpayload-test",
    metadata: {
      output: "ls: /nonexistent-hookpayload-test: No such file or directory\n",
      exit: 1,
      truncated: false,
    },
    output: "ls: /nonexistent-hookpayload-test: No such file or directory\n",
  },
}

const okBash = {
  input: {
    tool: "bash",
    sessionID: "ses_e6b7b9839ffeKUP5fNHsdiEPPU",
    callID: "call_205ce4c4b76543288a7c245d",
    args: { command: "thrum send --to @someone --stdin <<'EOF'\nREADY\nEOF", timeout: 30000 },
  },
  output: {
    title: "thrum send --to @someone --stdin",
    metadata: { output: "ok\n", exit: 0, truncated: false },
    output: "ok\n",
  },
}

const edit = {
  input: {
    tool: "edit",
    sessionID: "ses_e6b7b9839ffeKUP5fNHsdiEPPU",
    callID: "call_c44ada5aa666492993d527d0",
    args: { filePath: "~/wt/.thrum/hookpayload-scratch.txt", newString: "EDITED_TOKEN", oldString: "FAKE_TOKEN" },
  },
  output: {
    metadata: {
      diagnostics: {},
      diff: `Index: ~/wt/.thrum/hookpayload-scratch.txt\n@@ -1,1 +1,1 @@\n-FAKE_TOKEN=${FAKE_SECRET}\n+EDITED_TOKEN=${FAKE_SECRET}\n`,
      filediff: {
        file: "~/wt/.thrum/hookpayload-scratch.txt",
        patch: "Index: ~/wt/.thrum/hookpayload-scratch.txt\n@@ -1,1 +1,1 @@\n-FAKE_TOKEN=ghp_FAKE\n",
        additions: 1,
        deletions: 1,
      },
      truncated: false,
    },
    title: ".thrum/hookpayload-scratch.txt",
    output: "Edit applied successfully.",
  },
}

async function afterPayload(sample: { input: unknown; output: unknown }) {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  await h.after(sample.input, sample.output)
  assert.equal(calls.length, 1)
  return { raw: calls[0].payload, parsed: JSON.parse(calls[0].payload) }
}

test("failing bash (metadata.exit 1) carries exit=1 in tool_response", async () => {
  const { parsed } = await afterPayload(failingBash)
  assert.deepEqual(parsed.tool_response, {
    title: "ls /nonexistent-hookpayload-test",
    output: "ls: /nonexistent-hookpayload-test: No such file or directory\n",
    exit: 1,
  })
})

test("successful bash (metadata.exit 0) carries exit=0", async () => {
  const { parsed } = await afterPayload(okBash)
  assert.equal(parsed.tool_response.exit, 0)
  assert.deepEqual(Object.keys(parsed.tool_response).sort(), ["exit", "output", "title"])
})

test("edit has no metadata.exit: exit omitted and metadata.diff/filediff never forwarded", async () => {
  const { raw, parsed } = await afterPayload(edit)
  assert.deepEqual(parsed.tool_response, {
    title: ".thrum/hookpayload-scratch.txt",
    output: "Edit applied successfully.",
  })
  assert.equal("exit" in parsed.tool_response, false)
  assert.equal(raw.includes("ghp_FAKE"), false)
  assert.equal(raw.includes("Index:"), false)
  assert.equal(raw.includes("filediff"), false)
  assert.equal(raw.includes('"diff"'), false)
})

test("non-numeric metadata.exit is omitted; only exit is taken from metadata", async () => {
  for (const exit of ["1", null, undefined, {}, true]) {
    const { parsed } = await afterPayload({
      input: failingBash.input,
      output: { title: "t", output: "o", metadata: { exit, diff: "SECRETDIFF", extra: "x" } },
    })
    assert.equal("exit" in parsed.tool_response, false, `exit=${String(exit)} must be omitted`)
    assert.equal(JSON.stringify(parsed).includes("SECRETDIFF"), false)
  }
  const { parsed } = await afterPayload({
    input: failingBash.input,
    output: { title: "t", output: "o", metadata: { exit: 137, diff: "SECRETDIFF" } },
  })
  assert.equal(parsed.tool_response.exit, 137)
  assert.equal(JSON.stringify(parsed).includes("SECRETDIFF"), false)
})

test("a PreToolUse payload never carries exit", async () => {
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  await h.before(failingBash.input, { args: failingBash.input.args })
  assert.equal("tool_response" in JSON.parse(calls[0].payload), false)
})

// --- .thrum presence gate ---------------------------------------------------

test("no .thrum at cwd or any ancestor: runner never called (injected runner)", async () => {
  const f = fakeThrum("true", { thrumDir: false })
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: f.wt }, { run })
  await h.before(beforeIn, beforeOut)
  await h.after(afterIn, afterOut)
  assert.equal(calls.length, 0)
})

test("no .thrum anywhere: nothing is spawned (fake thrum records nothing)", async () => {
  const f = fakeThrum(RECORD, { thrumDir: false })
  const h = hooklogHooks({ directory: f.wt })
  await withPath(f.bin, async () => {
    await h.before(beforeIn, beforeOut)
    await h.after(afterIn, afterOut)
  })
  assert.equal(existsSync(join(f.rec, "argv")), false)
  assert.equal(existsSync(join(f.wt, ".thrum")), false)
})

test(".thrum in an ancestor directory: captured (control for the no-op test)", async () => {
  const f = fakeThrum(RECORD) // .thrum is at f.root, an ancestor of f.wt
  const deep = join(f.wt, "a", "b")
  mkdirSync(deep, { recursive: true })
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: deep }, { run })
  await h.before(beforeIn, beforeOut)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].cwd, deep)
  const real = hooklogHooks({ directory: deep })
  await withPath(f.bin, () => real.before(beforeIn, beforeOut))
  assert.equal(readFileSync(join(f.rec, "argv"), "utf8").trim(), "hooklog capture")
})

test("hasThrumDir is consulted with the chosen cwd", async () => {
  const seen: string[] = []
  const { calls, run } = recorder()
  const h = hooklogHooks({ directory: "/dir", worktree: "/wt" }, { run, hasThrumDir: (c) => { seen.push(c); return false } })
  await h.before(beforeIn, beforeOut)
  assert.deepEqual(seen, ["/wt"])
  assert.equal(calls.length, 0)
})

// --- composed handlers -------------------------------------------------------

const ASYNC = ".git/thrum-sync/a-sync"

test("composed before: a blocked command still throws and capture ran first", async () => {
  const order: string[] = []
  const run = async (payload: string) => {
    order.push(`capture:${JSON.parse(payload).hook_event_name}`)
  }
  const { before } = toolHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  await assert.rejects(
    () => before(
      { tool: "bash", sessionID: "s", callID: "c" },
      { args: { command: `git -C ${ASYNC} checkout main` } },
    ),
    /BLOCKED/,
  )
  assert.deepEqual(order, ["capture:PreToolUse"])
})

test("composed before: an allowed command resolves and is captured", async () => {
  const { calls, run } = recorder()
  const { before } = toolHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  await assert.doesNotReject(() => before(
    { tool: "bash", sessionID: "s", callID: "c" },
    { args: { command: `git -C ${ASYNC} add .` } },
  ))
  assert.equal(calls.length, 1)
})

test("composed before: a throwing runner neither masks the blocker nor blocks an allowed command", async () => {
  const run = async () => { throw new Error("capture down") }
  const { before } = toolHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  await assert.rejects(
    () => before(
      { tool: "bash", sessionID: "s", callID: "c" },
      { args: { command: `cd ${ASYNC}` } },
    ),
    /BLOCKED/,
  )
  await assert.doesNotReject(() => before(
    { tool: "bash", sessionID: "s", callID: "c" },
    { args: { command: "ls" } },
  ))
})

test("composed after: memory pointer still appends and hooklog still captures", async () => {
  const { calls, run } = recorder()
  const { after } = toolHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  const output = { title: "w", output: "wrote file", metadata: {} }
  await after({ tool: "write", sessionID: "s", callID: "c", args: { filePath: "/repo/AGENTS.md", content: "x" } }, output)
  assert.match(output.output, /Memory entry written: \/repo\/AGENTS\.md/)
  assert.equal(calls.length, 1)
  assert.equal(JSON.parse(calls[0].payload).hook_event_name, "PostToolUse")
})

test("composed after: a throwing runner does not affect the memory pointer result", async () => {
  const run = async () => { throw new Error("capture down") }
  const { after } = toolHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  const output = { title: "w", output: "wrote file", metadata: {} }
  await assert.doesNotReject(() => after(
    { tool: "write", sessionID: "s", callID: "c", args: { filePath: "/repo/AGENTS.md", content: "x" } },
    output,
  ))
  assert.match(output.output, /Memory entry written/)
})

test("composed after: a failing memory pointer does not stop hooklog capture", async () => {
  const { calls, run } = recorder()
  const { after } = toolHooks({ directory: "/d" }, { run, hasThrumDir: yes })
  // output.output is not a string and args missing: memory-pointer must not take capture down.
  await after({ tool: "write", sessionID: "s", callID: "c" } as never, { title: "t", output: "x" })
  assert.equal(calls.length, 1)
})
