// tool.execute.before / tool.execute.after hooks: feed `thrum hooklog capture`
// so each tool call writes a PreToolUse / PostToolUse record pair to
// hooklog.jsonl, the same pair Claude's wiring produces.
//
// `capture` reads Claude-shaped JSON on stdin and finds the repo by walking up
// from its cwd, so this shim builds that payload from the OpenCode envelope and
// runs the CLI in the worktree. It never throws or rejects: a hooklog failure
// must not break the tool call, and a throw from tool.execute.before would
// abort it.
import { execFile } from "node:child_process"
import { existsSync } from "node:fs"
import { dirname, join } from "node:path"

export type Runner = (payload: string, cwd: string) => Promise<void>

export interface HooklogOptions {
  directory: string
  worktree?: string
}

export interface HooklogDeps {
  /** Test seam: replaces the `thrum hooklog capture` spawn. */
  run?: Runner
  /** Test seam: whether a .thrum directory exists at cwd or an ancestor. */
  hasThrumDir?: (cwd: string) => boolean
  /** Spawn timeout for the default runner. */
  timeoutMs?: number
}

const DEFAULT_TIMEOUT_MS = 5000

export function hooklogHooks(opts: HooklogOptions, deps: HooklogDeps = {}) {
  // OpenCode reports worktree "/" for a directory that is not a git repo.
  const cwd = opts.worktree && opts.worktree !== "/" ? opts.worktree : opts.directory
  const hasThrumDir = deps.hasThrumDir ?? defaultHasThrumDir
  const run: Runner = deps.run ?? defaultRunner(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS)

  const capture = async (payload: Record<string, unknown>): Promise<void> => {
    try {
      // The plugin is installed globally; `capture` creates ./.thrum/var/log
      // when it finds no .thrum, so stay out of projects that are not thrum's.
      if (!hasThrumDir(cwd)) return
      await run(JSON.stringify(withoutUndefined({ ...payload, cwd })), cwd)
    } catch {
      // Fail open: capture is best-effort.
    }
  }

  return {
    before: async (input: any, output: any): Promise<void> => {
      try {
        await capture({
          hook_event_name: "PreToolUse",
          tool_name: input?.tool,
          tool_use_id: input?.callID,
          session_id: input?.sessionID,
          tool_input: output?.args,
        })
      } catch {
        // Fail open.
      }
    },
    after: async (input: any, output: any): Promise<void> => {
      try {
        await capture({
          hook_event_name: "PostToolUse",
          tool_name: input?.tool,
          tool_use_id: input?.callID,
          session_id: input?.sessionID,
          tool_input: input?.args ?? {},
          // metadata.exit is the only failure signal OpenCode gives (a failing bash call
          // still fires this hook normally). The rest of metadata is dropped on purpose:
          // edit's diff/filediff can be large and carry secrets.
          tool_response: withoutUndefined({
            title: output?.title,
            output: output?.output,
            exit: typeof output?.metadata?.exit === "number" ? output.metadata.exit : undefined,
          }),
        })
      } catch {
        // Fail open.
      }
    },
  }
}

/** True when a .thrum directory exists at dir or any ancestor. */
function defaultHasThrumDir(dir: string): boolean {
  let cur = dir
  for (;;) {
    if (existsSync(join(cur, ".thrum"))) return true
    const parent = dirname(cur)
    if (parent === cur) return false
    cur = parent
  }
}

function withoutUndefined<T extends Record<string, unknown>>(obj: T): T {
  return Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== undefined)) as T
}

function defaultRunner(timeoutMs: number): Runner {
  return (payload, cwd) =>
    new Promise<void>((resolve) => {
      try {
        const child = execFile(
          "thrum",
          ["hooklog", "capture"],
          { cwd, timeout: timeoutMs },
          () => resolve(),
        )
        child.on("error", () => resolve())
        child.on("exit", () => resolve())
        // A spawn failure or early exit closes stdin with EPIPE; swallow it.
        child.stdin?.on("error", () => {})
        child.stdin?.end(payload)
      } catch {
        resolve()
      }
    })
}
