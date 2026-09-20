<#
  patch-mem0-plugin.ps1

  Makes @mem0/opencode-plugin's Bun-targeted dist/index.js loadable and
  non-blocking under Node (the opencode DESKTOP app runs plugins inside
  Electron / Node, not Bun).

  It applies TWO independent, idempotent patches:

  PATCH A - Node compatibility
    The bundle's only Bun-ism is:
        var __require = import.meta.require;
    Under Node import.meta.require is undefined, so every __require(...) call
    throws "__require is not a function" and the whole plugin fails to load.
    We rewrite it to Node's createRequire(import.meta.url), which works under
    BOTH Node and Bun, so it is safe to apply unconditionally.

  PATCH B - no Bun shell in the plugin factory (Agent-tab hang fix)
    The bundle resolves git info with opencode's $ (Bun shell):
        const r = await $`git branch --show-current`.quiet();
    Calling $ from inside a plugin factory never settles when opencode is
    spawned as an ACP backend (the embedded Obsidian Copilot / Zed use case):
    the factory never returns, ACP `session/new` never answers, and the host
    stays on "Loading agent models..." forever.
    We replace those calls with node:child_process execFileSync (4s timeout,
    explicit cwd) and add a MEM0_BRANCH override. Pure git shell-out change;
    memory behaviour is identical.

  Idempotent: running it twice changes nothing the second time.

  Usage:
    powershell -ExecutionPolicy Bypass -File patch-mem0-plugin.ps1 -PluginDir <dir>
#>
param(
  [Parameter(Mandatory = $true)][string]$PluginDir
)

$ErrorActionPreference = "Stop"

$index = Join-Path $PluginDir "dist\index.js"
if (-not (Test-Path -LiteralPath $index)) {
  throw "not found: $index"
}

$text = [System.IO.File]::ReadAllText($index)
$changed = $false

# ---------------------------------------------------------------- PATCH A ---
$alreadyRequire = "__createRequire(import.meta.url)"
$needleRequire  = "var __require = import.meta.require;"
$requireLines   = @(
  "import { createRequire as __createRequire } from `"node:module`";"
  "var __require = __createRequire(import.meta.url);"
)
$requireReplacement = ($requireLines -join "`r`n")

if ($text.Contains($alreadyRequire)) {
  # already done
} elseif ($text.Contains($needleRequire)) {
  $text = $text.Replace($needleRequire, $requireReplacement)
  $changed = $true
  Write-Host "   + patch A: Bun require -> Node createRequire"
} else {
  $requirePattern = 'var\s+__require\s*=\s*import\.meta\.require\s*;'
  if ([regex]::IsMatch($text, $requirePattern)) {
    $text = [regex]::Replace($text, $requirePattern, $requireReplacement.Replace('$', '$$'))
    $changed = $true
    Write-Host "   + patch A: Bun require -> Node createRequire (regex)"
  }
}

# ---------------------------------------------------------------- PATCH B ---
$alreadyGit = "__execFileSync"

$gitLines = @(
  'import { execFileSync as __execFileSync } from "node:child_process";'
  'function __git(args, dir) {'
  '  try {'
  '    return __execFileSync("git", args, { timeout: 4000, stdio: ["ignore", "pipe", "ignore"], cwd: dir || process.cwd() }).toString().trim();'
  '  } catch {'
  '    return "";'
  '  }'
  '}'
  'async function getProjectId(dir) {'
  '  if (process.env.MEM0_APP_ID)'
  '    return process.env.MEM0_APP_ID;'
  '  const remote = __git(["remote", "get-url", "origin"], dir);'
  '  const project = remote ? parseProjectFromRemote(remote) : null;'
  '  if (project)'
  '    return project;'
  '  const top = __git(["rev-parse", "--show-toplevel"], dir);'
  '  if (top)'
  '    return basename(top);'
  '  return basename(dir || process.cwd());'
  '}'
  'async function getBranch(dir) {'
  '  if (process.env.MEM0_BRANCH)'
  '    return process.env.MEM0_BRANCH;'
  '  return __git(["branch", "--show-current"], dir) || "main";'
  '}'
)
$gitBlock = ($gitLines -join "`n")

$fnPattern = 'async function getProjectId\(\$\)\s*\{[\s\S]*?\n\}\nasync function getBranch\(\$\)\s*\{[\s\S]*?\n\}'
$ctxNeedle = 'const { $, client } = ctx;'

if ($text.Contains($alreadyGit)) {
  # already done
} elseif ([regex]::IsMatch($text, $fnPattern)) {
  $text = [regex]::Replace($text, $fnPattern, { param($m) $gitBlock })
  if ($text.Contains($ctxNeedle)) {
    $ctxReplacement = $ctxNeedle + "`n" + '  const __dir = ctx.directory || ctx.worktree || process.cwd();'
    $text = $text.Replace($ctxNeedle, $ctxReplacement)
  }
  $text = $text.Replace('await getProjectId($)', 'await getProjectId(__dir)')
  $text = $text.Replace('await getBranch($)', 'await getBranch(__dir)')
  $changed = $true
  Write-Host "   + patch B: shell-out git -> execFileSync (Agent-hang fix)"
}

# ---------------------------------------------------------------- WRITE -----
if ($changed) {
  [System.IO.File]::WriteAllText($index, $text, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "   + patched dist/index.js"
} else {
  Write-Host "   = already patched (dist/index.js)"
}
exit 0
