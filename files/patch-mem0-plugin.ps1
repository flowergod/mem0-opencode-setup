<#
  patch-mem0-plugin.ps1

  Makes @mem0/opencode-plugin's Bun-targeted dist/index.js loadable under Node
  (the opencode DESKTOP app runs plugins inside Electron / Node, not Bun).

  The bundle's ONLY Bun-ism is:
      var __require = import.meta.require;
  Under Node import.meta.require is undefined, so every __require(...) call
  throws "__require is not a function" and the whole plugin fails to load.

  We rewrite it to Node's createRequire(import.meta.url), which works under
  BOTH Node and Bun, so it is safe to apply unconditionally.

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

$already = "__createRequire(import.meta.url)"
$needle  = "var __require = import.meta.require;"
$lines   = @(
  "import { createRequire as __createRequire } from `"node:module`";"
  "var __require = __createRequire(import.meta.url);"
)
$replacement = ($lines -join "`r`n")

if ($text.Contains($already)) {
  Write-Host "   = already patched (dist/index.js)"
  exit 0
}

if ($text.Contains($needle)) {
  $patched = $text.Replace($needle, $replacement)
  [System.IO.File]::WriteAllText($index, $patched, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "   + patched dist/index.js (Bun require -> Node createRequire)"
  exit 0
}

# Fallback: tolerate whitespace variations of the same line.
$pattern = 'var\s+__require\s*=\s*import\.meta\.require\s*;'
if ([regex]::IsMatch($text, $pattern)) {
  $patched = [regex]::Replace($text, $pattern, $replacement.Replace('$', '$$'))
  [System.IO.File]::WriteAllText($index, $patched, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "   + patched dist/index.js (regex match)"
  exit 0
}

Write-Host "   ! patch target not found - bundle looks already Node-compatible; left as-is"
exit 0
