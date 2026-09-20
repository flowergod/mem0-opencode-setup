# mem0-opencode-setup

**English** | [简体中文](README.zh-CN.md)

One-command installer for a **persistent, cross-device memory system** in
[opencode](https://opencode.ai), backed by [Mem0](https://mem0.ai).

Version 2 ships a **vendored, Node-patched** copy of `@mem0/opencode-plugin`, so the
same setup loads in both the opencode **desktop app** (Electron / Node) and the
**CLI / web** build (Bun). Everything is pinned to one memory scope
(`user_id = "opencode"`, `app_id = "opencode"`), so every machine shares one memory
space and behaves identically.

## Install (Windows)

Pick one.

**A. Self-contained file** — download `mem0-setup.ps1`, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mem0-setup.ps1 -ApiKey "m0-xxxxxxxx"
```

**B. True one-liner** (fetch and run, with args):

```powershell
powershell -NoProfile -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/flowergod/mem0-opencode-setup/main/mem0-setup.ps1))) -ApiKey 'm0-xxxxxxxx'"
```

Omit `-ApiKey` and set it yourself afterwards (`setx MEM0_API_KEY "m0-..."`).

Preview without changing anything: add `-DryRun`.

Then **fully restart opencode** — plugins load only at process start (there is no hot reload).

## Options

| Flag | Effect |
| --- | --- |
| `-DryRun` | Show what would be removed/installed; write nothing |
| `-SkipCleanup` | Do not touch other tools' configs |
| `-SkipPlugin` | Reuse the existing `mem0-plugin\`, do not re-download |
| `-RefreshPlugin` | Force a fresh download of the plugin |
| `-PluginVersion 0.4.0` | Pin a different plugin version |
| `-Verify` | Health check only, no changes |
| `-SkillOnly` | Install/open the opencode skill files only |
| `-ApiKey "m0-..."` | Also store `MEM0_API_KEY` in the user environment |

## What it does

1. **Reconcile / cleanup first** — removes every other mem0 integration and the *old*
   setup, backing everything up first:
   - other tools: Claude, Codex, Cursor, Windsurf, VS Code
   - old opencode setup: the `mcp.mem0` block, the `@mem0/opencode-plugin` npm spec,
     and `plugins/mem0-memory.js` (the old custom plugin)
   - env checks: `MEM0_USER_ID` / `MEM0_APP_ID` must be `opencode`; `MEM0_API_KEY` present
2. Vendors a **Node-patched** copy of `@mem0/opencode-plugin` into
   `~/.config/opencode/mem0-plugin/`.
3. Installs `memory-protocol.md`.
4. Merges `instructions` + the plugin's absolute path into `opencode.jsonc`.
5. Verifies, then reminds you to restart.

Restart opencode afterwards.

## Why the plugin is patched

`@mem0/opencode-plugin@0.4.0` is published as a **Bun** bundle. Its only Bun-specific
line is:

```js
var __require = import.meta.require;   // dist/index.js
```

- opencode **CLI / web** (Bun runtime): fine, the plugin loads.
- opencode **desktop app** (Electron / **Node** runtime): `import.meta.require` is
  `undefined`, so every `__require(...)` throws `__require is not a function` and the
  whole plugin (tools, skills, hooks) fails to load silently.

The fix is one line — replace it with Node's `createRequire(import.meta.url)`, which
works on **both** Node and Bun. `files/patch-mem0-plugin.ps1` does this idempotently,
and the installer vendors the patched plugin so opencode loads it by absolute path.

## After install

The installer also drops an opencode **skill** (`mem0-opencode-setup`). Once opencode is
restarted you can invoke it in natural language, e.g. "sync/reinstall the mem0 memory
setup on this machine".

## Verify after restart

1. `opencode debug config` → shows the `mem0-plugin` path and the `/mem0-*` commands.
2. In opencode run `/mem0-status` → all checks pass.
3. Ask it to remember something, then recall it in a new session.
4. app.mem0.ai → Memories, filter `user_id = opencode`, `app_id = opencode`.

Same API key + same scope = **shared across devices**.

## Behavior installed

- **recall** — once per session, injected into the first user message before the model call
- **save** — user messages captured live; session state captured on compaction; errors captured from tool output
- **tools** — 10 memory tools (`add_memory`, `search_memories`, `get_memories`,
  `get_memory`, `update_memory`, `delete_memory`, `delete_all_memories`,
  `delete_entities`, `list_entities`, `get_event_status`)
- **commands** — `/mem0-remember`, `/mem0-search`, `/mem0-status`, `/mem0-tour`,
  `/mem0-scope`, `/mem0-forget`, `/mem0-context-loader`

## Repo layout

| Path | Purpose |
| --- | --- |
| `mem0-setup.ps1` | Self-contained one-liner: carries the whole skill, then runs the installer |
| `install.ps1` | The installer (idempotent; supports `-DryRun` / `-Verify`) |
| `SKILL.md` | opencode skill definition (agent-facing instructions) |
| `files/memory-protocol.md` | Protocol that tells the agent to auto store/recall |
| `files/patch-mem0-plugin.ps1` | The Node compatibility patch (idempotent) |
| `files/opencode-mem0.snippet.jsonc` | Config snippet for manual merging |

## Rollback

Backups live in `~/.config/opencode/mem0-setup-backup/<timestamp>/`. Restore from there,
or delete `memory-protocol.md`, the `mem0-plugin\` folder, and the mem0 entries in
`opencode.jsonc`.

## Notes

- Windows only (PowerShell 5.1+). macOS / Linux need their own script.
- Requires Node (for the patch self-test) and either `npm.cmd` or network access to fetch
  the plugin on first install.
- `user_id` is intentionally hard-coded to `"opencode"`. Change it in the protocol,
  the config, and the env vars together if you ever need a different scope.
