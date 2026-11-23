// Regression test: a stray .thrum/identity.json must never change the agent
// identity environment. Nothing in thrum writes that file (identities live in
// .thrum/identities/<name>.json), so the plugin must not register a shell.env
// hook that reads it; such a hook would overwrite the launch script's correct
// THRUM_NAME / THRUM_ROLE on the next shell call.
//
// The plugin server runs installers that write under HOME / XDG_CONFIG_HOME,
// so both are pointed at a throwaway directory before the server is created.
// node --test runs each file in its own process, so this does not leak.
//
// Run: npm test  (builds, then `node --test dist`)

import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import plugin from "./index.js"

test("plugin does not register a shell.env identity hook; stray identity.json leaves env untouched", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "oc-index-test-"))
  const savedHome = process.env.HOME
  const savedXdg = process.env.XDG_CONFIG_HOME
  try {
    process.env.HOME = path.join(root, "home")
    process.env.XDG_CONFIG_HOME = path.join(root, "xdg")
    fs.mkdirSync(path.join(root, "project", ".thrum"), { recursive: true })
    fs.writeFileSync(
      path.join(root, "project", ".thrum", "identity.json"),
      JSON.stringify({ agent_id: "stray_agent", role: "stray", module: "x" }),
    )

    const ctx = {
      directory: path.join(root, "project"),
      worktree: path.join(root, "project"),
      client: { app: { log: async () => {} } },
    } as never
    const hooks = (await plugin.server(ctx)) as Record<string, unknown>

    // Control: the server really registered its hooks (a non-empty result).
    assert.equal(typeof hooks["tool.execute.before"], "function")

    // The identity hook must not be registered at all.
    assert.equal(hooks["shell.env"], undefined)

    // Behavioral form: even if a shell.env hook were registered, the env
    // already set by the launch script must survive a stray identity.json.
    const env: Record<string, string> = { THRUM_NAME: "impl_real", THRUM_ROLE: "implementer" }
    const shellEnv = hooks["shell.env"] as
      | ((i: { cwd: string }, o: { env: Record<string, string> }) => Promise<void>)
      | undefined
    if (shellEnv) {
      await shellEnv({ cwd: path.join(root, "project") }, { env })
    }
    assert.equal(env.THRUM_NAME, "impl_real")
    assert.equal(env.THRUM_ROLE, "implementer")
  } finally {
    if (savedHome === undefined) delete process.env.HOME
    else process.env.HOME = savedHome
    if (savedXdg === undefined) delete process.env.XDG_CONFIG_HOME
    else process.env.XDG_CONFIG_HOME = savedXdg
    fs.rmSync(root, { recursive: true, force: true })
  }
})
