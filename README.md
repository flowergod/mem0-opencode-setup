# mem0-opencode-setup

One-command installer for a **persistent, cross-device memory system** in
[opencode](https://opencode.ai), backed by [Mem0](https://mem0.ai).

It installs three things and pins them to a single memory scope
(`user_id = "opencode"`), so every machine shares one memory space and behaves identically:

- **MCP server** — the mem0 tools for the agent
- **Memory protocol** (`memory-protocol.md`) — tells the agent to auto store/recall
- **Plugin** (`mem0-memory.js`) — automatic recall (before each model call) and
  debounced save (after a session goes idle)

Before installing, it **detects and removes any other mem0 integrations** on the
machine (opencode / Claude / Codex / Cursor / Windsurf / VS Code). All changes are
backed up first.

## Install (Windows)

Pick one.

**A. Self-contained file** — download `mem0-setup.ps1`, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mem0-setup.ps1 -ApiKey "m0-xxxxxxxx"
```

**B. True one-liner** (fetches and runs):

```powershell
powershell -NoProfile -Command "irm https://raw.githubusercontent.com/flowergod/mem0-opencode-setup/main/mem0-setup.ps1 | iex"
```

_(After step B you still need to pass your key; set it separately with
`setx MEM0_API_KEY "m0-..."` and restart, or clone and run with `-ApiKey`.)_

Preview without changing anything: add `-DryRun`.

## Options

| Flag | Effect |
| --- | --- |
| `-DryRun` | Show what would be removed/installed; write nothing |
| `-SkipCleanup` | Do not touch other configs |
| `-SkillOnly` | Install only the opencode skill files |
| `-ApiKey "m0-..."` | Also store `MEM0_API_KEY` in the user environment |

## What it does

1. **Detect & remove other mem0 integrations** (backed up first)
2. Install `memory-protocol.md` and `plugins/mem0-memory.js` into `~/.config/opencode/`
3. Merge the mem0 MCP server + instructions into `opencode.jsonc`
4. Store `MEM0_API_KEY` (optional)
5. Remind you to restart opencode

Restart opencode afterwards.

## After install

The installer also drops an opencode **skill** (`mem0-opencode-setup`). Once
opencode is restarted you can invoke it in natural language, e.g.
"sync/reinstall the mem0 memory setup on this machine".

## Behavior installed

- **recall** — once per session, injected into the system prompt *before* the model call
- **save** — debounced 5 min after a session goes idle (or at 10 pending messages)
- knobs at the top of `files/mem0-memory.js`: `SAVE_DEBOUNCE_MS`, `MAX_PENDING`,
  `MIN_SCORE`, `MAX_MEMORIES`

## Rollback

Backups live in `~/.config/opencode/mem0-setup-backup/<timestamp>/`. Restore from
there, or delete `memory-protocol.md`, the `mem0-memory.js` plugin, and the `mem0`
entry in `opencode.jsonc`.

## Notes

- Windows only (PowerShell 5.1+).
- `user_id` is intentionally hard-coded to `"opencode"` in both the protocol and the
  plugin. Change it in **both** places if you ever need a different scope.
