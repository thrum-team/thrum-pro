// Composes the plugin's tool.execute.before / tool.execute.after handlers.
//
// OpenCode takes ONE function per hook key, so the hooklog capture, the
// a-sync worktree guard and the memory pointer are chained here.
//
//   before: capture first, so a blocked attempt is still logged (as an unpaired
//           PreToolUse), then the guard, whose throw aborts the call and must
//           propagate unchanged.
//   after:  memory pointer and capture are independent; neither's failure may
//           affect the other.
import { blockSyncCdHook } from "./block-sync-cd.js"
import { memoryPointerHook } from "./memory-pointer.js"
import { hooklogHooks, type HooklogDeps, type HooklogOptions } from "./hooklog.js"

export function toolHooks(opts: HooklogOptions, deps: HooklogDeps = {}) {
  const hooklog = hooklogHooks(opts, deps)
  const blocker = blockSyncCdHook()
  const memoryPointer = memoryPointerHook()

  return {
    before: async (input: any, output: any): Promise<void> => {
      await hooklog.before(input, output)
      await blocker(input, output)
    },
    after: async (input: any, output: any): Promise<void> => {
      const results = await Promise.allSettled([
        memoryPointer(input, output),
        hooklog.after(input, output),
      ])
      // The memory pointer's behaviour is unchanged: a failure there still
      // surfaces, but only after hooklog capture has run.
      const memory = results[0]
      if (memory.status === "rejected") throw memory.reason
    },
  }
}
