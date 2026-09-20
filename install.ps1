<#
  mem0-opencode-setup  (Windows)  -- v2, "vendored + patched plugin" edition

  Installs the standard mem0 automatic-memory system for opencode:

    - <config>\memory-protocol.md      instructions that tell the agent to auto recall/save
    - <config>\mem0-plugin\            vendored @mem0/opencode-plugin (Node-patched)
    - opencode.jsonc                   instructions + plugin (absolute path)

  WHY VENDORED + PATCHED
    @mem0/opencode-plugin@0.4.0 ships a Bun-targeted bundle whose only Bun-ism is
    `var __require = import.meta.require;`. The opencode DESKTOP app runs plugins
    inside Electron / Node, where import.meta.require is undefined, so every
    `__require(...)` throws "__require is not a function" and the plugin (tools,
    skills, hooks) silently fails to load. Rewriting that one line to Node's
    `createRequire(import.meta.url)` works under BOTH Node and Bun, so we vendor a
    patched copy and make opencode load it by absolute path.

  STEP 0 (before everything) RECONCILES THE MACHINE
    - detects & removes OTHER mem0 integrations (Claude / Codex / Cursor / Windsurf / VS Code)
    - removes the OLD opencode setup (mem0 MCP block, npm plugin spec, plugins\mem0-memory.js)
    - checks user env vars (MEM0_API_KEY / MEM0_USER_ID / MEM0_APP_ID) and fixes the scope
    Everything it touches is backed up to <config>\mem0-setup-backup\<timestamp>\ first.

  Usage (from a normal PowerShell):
    powershell -ExecutionPolicy Bypass -File install.ps1                  # apply
    powershell -ExecutionPolicy Bypass -File install.ps1 -DryRun          # preview only
    powershell -ExecutionPolicy Bypass -File install.ps1 -ApiKey "m0-..." # also store MEM0_API_KEY
    powershell -ExecutionPolicy Bypass -File install.ps1 -SkipCleanup     # do not touch other configs
    powershell -ExecutionPolicy Bypass -File install.ps1 -SkipPlugin      # reuse existing mem0-plugin\
    powershell -ExecutionPolicy Bypass -File install.ps1 -RefreshPlugin   # re-download the plugin
    powershell -ExecutionPolicy Bypass -File install.ps1 -Verify          # check only, change nothing
#>
param(
  [switch]$DryRun,
  [switch]$SkipCleanup,
  [switch]$SkipPlugin,
  [switch]$RefreshPlugin,
  [switch]$Verify,
  [string]$ApiKey = "",
  [string]$PluginVersion = "0.4.0"
)

$ErrorActionPreference = "Stop"
$script:BackedUp = @{}
$script:Changed  = @()
$script:Found    = $false

$UserHome      = $env:USERPROFILE
$OpencodeDir   = Join-Path $UserHome ".config\opencode"
$PluginsDir    = Join-Path $OpencodeDir "plugins"
$ProtocolPath  = Join-Path $OpencodeDir "memory-protocol.md"
$PluginDir     = Join-Path $OpencodeDir "mem0-plugin"
$OldPluginFile = Join-Path $PluginsDir "mem0-memory.js"
$Stamp         = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir     = Join-Path $OpencodeDir "mem0-setup-backup\$Stamp"
$PackageDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$FilesDir      = Join-Path $PackageDir "files"
$PatchScript   = Join-Path $FilesDir "patch-mem0-plugin.ps1"
$SkillDir      = $PackageDir

function Step($n, $t) { Write-Host ""; Write-Host "== [$n] $t" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "   + $m" -ForegroundColor Green }
function Warn2($m) { Write-Host "   ! $m" -ForegroundColor Yellow }
function Info($m)  { Write-Host "   - $m" }
function Note($m)  { $script:Changed += $m }

function Write-Utf8NoBom([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Backup-File([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  if ($DryRun) { Info "would back up: $path"; return }
  $rel = $path
  if ($rel.StartsWith($UserHome, [System.StringComparison]::OrdinalIgnoreCase)) {
    $rel = $rel.Substring($UserHome.Length).TrimStart('\', '/')
  } else {
    $rel = Split-Path -Leaf $path
  }
  $rel = $rel -replace '[\\/]', "__"
  if ($script:BackedUp.ContainsKey($rel)) { return }
  $script:BackedUp[$rel] = $true
  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  Copy-Item -LiteralPath $path -Destination (Join-Path $BackupDir $rel) -Force
  Ok "backed up -> mem0-setup-backup\$Stamp\$rel"
}

# ---------------- JSONC helpers (parse JSON-with-comments/trailing-commas) ----------------
function Remove-JsonComments([string]$text) {
  $sb = New-Object System.Text.StringBuilder
  $inStr = $false; $esc = $false; $i = 0
  while ($i -lt $text.Length) {
    $c = $text[$i]
    if ($inStr) {
      [void]$sb.Append($c)
      if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
      $i++; continue
    }
    if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c); $i++; continue }
    if ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '/') {
      while ($i -lt $text.Length -and $text[$i] -ne "`n") { $i++ }
      continue
    }
    if ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '*') {
      $i += 2
      while ($i + 1 -lt $text.Length -and -not ($text[$i] -eq '*' -and $text[$i + 1] -eq '/')) { $i++ }
      $i += 2; continue
    }
    [void]$sb.Append($c); $i++
  }
  return $sb.ToString()
}

function Remove-TrailingCommas([string]$text) {
  $sb = New-Object System.Text.StringBuilder
  $inStr = $false; $esc = $false; $i = 0
  while ($i -lt $text.Length) {
    $c = $text[$i]
    if ($inStr) {
      [void]$sb.Append($c)
      if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
      $i++; continue
    }
    if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c); $i++; continue }
    if ($c -eq ',') {
      $j = $i + 1
      while ($j -lt $text.Length -and [char]::IsWhiteSpace($text[$j])) { $j++ }
      if ($j -lt $text.Length -and ($text[$j] -eq '}' -or $text[$j] -eq ']')) { $i++; continue }
    }
    [void]$sb.Append($c); $i++
  }
  return $sb.ToString()
}

function Read-Jsonc([string]$path) {
  $raw = Get-Content -LiteralPath $path -Raw
  $clean = Remove-TrailingCommas (Remove-JsonComments $raw)
  return $clean | ConvertFrom-Json
}

function ConvertTo-HashtableDeep($obj) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
    return $h
  }
  if ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
    $a = @(); foreach ($i in $obj) { $a += ,(ConvertTo-HashtableDeep $i) }; return ,$a
  }
  return $obj
}

# Drop any property whose name mentions mem0, and any array item that does. Recursive.
function Clean-Mem0($value) {
  if ($null -eq $value) { return $null }
  if ($value -is [System.Management.Automation.PSCustomObject]) {
    $o = [ordered]@{}
    foreach ($p in $value.PSObject.Properties) {
      if ($p.Name -match '(?i)mem0') { continue }
      $o[$p.Name] = Clean-Mem0 $p.Value
    }
    return [PSCustomObject]$o
  }
  if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
    $a = @()
    foreach ($item in $value) {
      if ($item -is [string] -and $item -match '(?i)mem0') { continue }
      $a += ,(Clean-Mem0 $item)
    }
    return ,$a
  }
  return $value
}

function Test-FileMentionsMem0([string]$path) {
  try { $c = Get-Content -LiteralPath $path -Raw -ErrorAction Stop } catch { return $false }
  return ($c -match '(?i)mem0')
}

function Test-PluginLoadable([string]$dir) {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { return $null }
  $index = Join-Path $dir "dist\index.js"
  if (-not (Test-Path -LiteralPath $index)) { return $false }
  $uri = "file:///" + ($index -replace '\\', '/')
  $probe = Join-Path $env:TEMP ("mem0-loadprobe-$Stamp.mjs")
  $js = "import('$uri').then(m => process.exit(typeof m.default === 'function' ? 0 : 2)).catch(e => { console.error(String(e && e.message || e)); process.exit(3) })"
  Write-Utf8NoBom $probe $js
  try {
    $res = & $node.Source $probe 2>&1
    $code = $LASTEXITCODE
  } finally {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  }
  if ($code -ne 0 -and $res) { Warn2 "load probe output: $($res -join ' ')" }
  return ($code -eq 0)
}

function Get-OpencodeCli {
  $cands = @(
    (Join-Path $env:APPDATA "npm\node_modules\opencode-ai\bin\opencode.exe"),
    (Join-Path $UserHome ".opencode\bin\opencode.exe"),
    (Join-Path $UserHome ".local\bin\opencode.exe")
  )
  foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
  $g = Get-Command opencode.exe -ErrorAction SilentlyContinue
  if ($g) { return $g.Source }
  return $null
}

# ---------------------------------------------------------------- targets
$JsonTargets = @(
  (Join-Path $OpencodeDir "opencode.json"),
  (Join-Path $OpencodeDir "opencode.jsonc"),
  (Join-Path $UserHome ".claude.json"),
  (Join-Path $UserHome ".claude\settings.json"),
  (Join-Path $UserHome ".claude\settings.local.json"),
  (Join-Path $UserHome ".cursor\mcp.json"),
  (Join-Path $UserHome ".codeium\windsurf\mcp_config.json"),
  (Join-Path $env:APPDATA "Code\User\settings.json")
)
$TomlTargets = @( (Join-Path $UserHome ".codex\config.toml") )
$OpencodeScanDirs = @( $PluginsDir, (Join-Path $OpencodeDir "skill"), (Join-Path $OpencodeDir "skills") )
$ExternalSkillDirs = @( (Join-Path $UserHome ".claude\skills"), (Join-Path $UserHome ".agents\skills") )

function Is-Excluded([string]$path) {
  $ex = @($ProtocolPath, $SkillDir, $PluginDir, (Join-Path $OpencodeDir "mem0-setup-backup"))
  foreach ($e in $ex) { if ($path.StartsWith($e, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
  return $false
}

# ============================================================
# VERIFY-ONLY MODE
# ============================================================
if ($Verify) {
  Step "V" "Verify current installation (no changes)"
  if (Test-Path -LiteralPath $ProtocolPath) { Ok "protocol present: $ProtocolPath" } else { Warn2 "protocol missing: $ProtocolPath" }
  $pkg = Join-Path $PluginDir "package.json"
  if (Test-Path -LiteralPath $pkg) {
    $v = (Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json).version
    Ok "plugin vendored: $PluginDir (v$v)"
  } else { Warn2 "plugin missing: $PluginDir" }
  $idx = Join-Path $PluginDir "dist\index.js"
  if (Test-Path -LiteralPath $idx) {
    $t = [System.IO.File]::ReadAllText($idx)
    if ($t.Contains("__createRequire(import.meta.url)")) { Ok "patch applied (Node-compatible)" }
    elseif ($t.Contains("import.meta.require")) { Warn2 "NOT patched - will fail under the desktop app" }
    else { Info "no Bun require line found (already compatible)" }
    $loadable = Test-PluginLoadable $PluginDir
    if ($loadable -eq $true) { Ok "plugin imports cleanly under Node" }
    elseif ($loadable -eq $false) { Warn2 "plugin failed to import under Node" }
  }
  foreach ($c in @("MEM0_API_KEY", "MEM0_USER_ID", "MEM0_APP_ID")) {
    $val = [Environment]::GetEnvironmentVariable($c, "User")
    if ($c -eq "MEM0_API_KEY") { if ($val) { Ok "$c set (len $($val.Length))" } else { Warn2 "$c NOT set" } }
    else { if ($val) { Ok "$c = $val" } else { Warn2 "$c NOT set" } }
  }
  $cli = Get-OpencodeCli
  if ($cli) {
    try {
      $cfg = & $cli debug config 2>$null | Out-String
      if ($cfg -match 'mem0-plugin') { Ok "opencode config resolves the mem0-plugin path" } else { Warn2 "opencode config does not reference mem0-plugin" }
      if ($cfg -match 'mem0-remember') { Ok "mem0 skills/commands registered" } else { Warn2 "mem0 commands not found in resolved config" }
    } catch { Warn2 "could not run 'opencode debug config': $($_.Exception.Message)" }
  } else { Info "opencode CLI not found - skip config resolution check" }
  Write-Host ""
  Write-Host "Verification complete." -ForegroundColor Cyan
  exit 0
}

# ============================================================
Step 0 "Reconcile: remove old / other mem0 setups, check env"
# ============================================================
if (-not $SkipCleanup) {
  # --- 0a. external tool configs (Claude / Cursor / Windsurf / VS Code) ---
  foreach ($f in $JsonTargets) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    if (Is-Excluded $f) { continue }
    if (-not (Test-FileMentionsMem0 $f)) { continue }
    $script:Found = $true
    Warn2 "mem0 reference in JSON config: $f"
    try {
      $obj = Read-Jsonc $f
      $cleaned = Clean-Mem0 $obj
      Backup-File $f
      if (-not $DryRun) {
        Write-Utf8NoBom $f ($cleaned | ConvertTo-Json -Depth 40)
        Ok "removed mem0 entries from $f"
        Note "cleaned $f"
      }
    } catch {
      Warn2 "could not parse $f (left untouched): $($_.Exception.Message)"
    }
  }

  # --- 0b. codex TOML ---
  foreach ($f in $TomlTargets) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    if (Is-Excluded $f) { continue }
    $lines = Get-Content -LiteralPath $f
    if (($lines -join "`n") -notmatch '(?i)mem0') { continue }
    $script:Found = $true
    Warn2 "mem0 reference in TOML config: $f"
    $out = New-Object System.Collections.ArrayList
    $skip = $false
    foreach ($ln in $lines) {
      if ($ln -match '^\s*\[') { $skip = ($ln -match '(?i)mem0') }
      if ($skip) { continue }
      if ($ln -match '(?i)mem0') { continue }
      [void]$out.Add($ln)
    }
    Backup-File $f
    if (-not $DryRun) {
      Write-Utf8NoBom $f ($out -join "`r`n")
      Ok "removed mem0 sections from $f"
      Note "cleaned $f"
    }
  }

  # --- 0c. old custom plugin inside the opencode plugins dir ---
  foreach ($old in @($OldPluginFile, "$OldPluginFile.disabled")) {
    if (Test-Path -LiteralPath $old) {
      $script:Found = $true
      Warn2 "old custom plugin present: $old"
      Backup-File $old
      if (-not $DryRun) {
        Remove-Item -LiteralPath $old -Force
        Ok "removed $old"
        Note "removed $old"
      }
    }
  }

  # --- 0d. any other mem0-named file under the opencode plugin/skill dirs ---
  foreach ($d in $OpencodeScanDirs) {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $p = $_.FullName
      if (Is-Excluded $p) { return }
      if ($_.Length -gt 2MB) { return }
      if ((-not ($_.Name -match '(?i)mem0')) -and (-not (Test-FileMentionsMem0 $p))) { return }
      $script:Found = $true
      Warn2 "stray mem0 file: $p"
      Backup-File $p
      if (-not $DryRun) { Remove-Item -LiteralPath $p -Force; Ok "removed $p"; Note "removed $p" }
    }
  }

  # --- 0e. external skill dirs: report only (never auto-delete someone's skills) ---
  foreach ($d in $ExternalSkillDirs) {
    if (-not (Test-Path -LiteralPath $d)) { continue }
    Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $p = $_.FullName
      if (Is-Excluded $p) { return }
      if ($_.Name -notmatch '(?i)mem0') { return }
      Info "note (not removed): mem0-named file outside opencode: $p"
    }
  }

  if (-not $script:Found) { Ok "no other / old mem0 integrations found" }
} else {
  Info "cleanup skipped (-SkipCleanup)"
}

# --- 0f. env vars ---
Step "0b" "Check user environment variables"
$wantEnv = [ordered]@{ MEM0_USER_ID = "opencode"; MEM0_APP_ID = "opencode" }
foreach ($k in $wantEnv.Keys) {
  $cur = [Environment]::GetEnvironmentVariable($k, "User")
  $want = $wantEnv[$k]
  if ($cur -eq $want) { Ok "$k = $want" }
  else {
    if ($cur) { Warn2 "$k was '$cur' -> setting to '$want'" } else { Info "$k not set -> setting to '$want'" }
    if (-not $DryRun) { [Environment]::SetEnvironmentVariable($k, $want, "User"); Note "set $k" }
  }
}
$existingKey = [Environment]::GetEnvironmentVariable("MEM0_API_KEY", "User")
if ($ApiKey -and $ApiKey.Trim().Length -gt 0) {
  if (-not $DryRun) { [Environment]::SetEnvironmentVariable("MEM0_API_KEY", $ApiKey.Trim(), "User"); Ok "stored MEM0_API_KEY (user env)"; Note "set MEM0_API_KEY" }
  else { Info "would store MEM0_API_KEY (user env)" }
} elseif ($existingKey) {
  Ok "MEM0_API_KEY already set (len $($existingKey.Length))"
} else {
  Warn2 "MEM0_API_KEY not set - pass -ApiKey `"m0-...`" or run: setx MEM0_API_KEY `"m0-...`""
}

# ============================================================
Step 1 "Install memory-protocol.md"
# ============================================================
if (-not (Test-Path -LiteralPath $OpencodeDir)) { New-Item -ItemType Directory -Force -Path $OpencodeDir | Out-Null }
$protoSrc = Join-Path $FilesDir "memory-protocol.md"
if (-not (Test-Path -LiteralPath $protoSrc)) { Warn2 "missing package file: $protoSrc" }
else {
  Backup-File $ProtocolPath
  if (-not $DryRun) { Copy-Item -LiteralPath $protoSrc -Destination $ProtocolPath -Force; Ok "installed $ProtocolPath"; Note "wrote memory-protocol.md" }
  else { Info "would install $ProtocolPath" }
}

# ============================================================
Step 2 "Vendor + patch @mem0/opencode-plugin"
# ============================================================
function Get-PluginFromRegistry {
  param([string]$Version, [string]$Work)
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($npm) {
    try {
      Info "npm pack @mem0/opencode-plugin@$Version"
      & $npm.Source pack "@mem0/opencode-plugin@$Version" --pack-destination $Work 2>&1 | Out-Null
      $tgz = Get-ChildItem -LiteralPath $Work -Filter "*.tgz" -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($tgz) {
        & tar.exe -xzf $tgz.FullName -C $Work 2>&1 | Out-Null
        if (Test-Path -LiteralPath (Join-Path $Work "package\dist\index.js")) { return (Join-Path $Work "package") }
      }
    } catch { Info "npm pack failed: $($_.Exception.Message)" }
  }
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://registry.npmjs.org/@mem0/opencode-plugin/-/opencode-plugin-$Version.tgz"
    $tgz = Join-Path $Work "plugin.tgz"
    Info "downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $tgz -UseBasicParsing
    & tar.exe -xzf $tgz -C $Work 2>&1 | Out-Null
    if (Test-Path -LiteralPath (Join-Path $Work "package\dist\index.js")) { return (Join-Path $Work "package") }
  } catch { Info "registry download failed: $($_.Exception.Message)" }
  foreach ($cache in @(
      (Join-Path $UserHome ".cache\opencode\packages\@mem0\opencode-plugin\node_modules\@mem0\opencode-plugin"),
      (Join-Path $UserHome ".cache\opencode\packages\@mem0\opencode-plugin@latest\node_modules\@mem0\opencode-plugin")
    )) {
    if (Test-Path -LiteralPath (Join-Path $cache "dist\index.js")) { Info "reusing local cache: $cache"; return $cache }
  }
  return $null
}

if ($SkipPlugin) {
  Info "plugin vendoring skipped (-SkipPlugin)"
} else {
  $havePlugin = Test-Path -LiteralPath (Join-Path $PluginDir "dist\index.js")
  if ($havePlugin -and -not $RefreshPlugin) {
    Info "reusing existing $PluginDir (-RefreshPlugin to re-download)"
  } else {
    $work = Join-Path $env:TEMP "mem0-plugin-$Stamp"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $src = Get-PluginFromRegistry -Version $PluginVersion -Work $work
    if (-not $src) {
      Warn2 "could not obtain @mem0/opencode-plugin@$PluginVersion (no npm, no network, no cache)"
      Warn2 "install it manually, then re-run with -SkipPlugin"
    } elseif (-not $DryRun) {
      New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
      foreach ($item in @("dist", "opencode-skills", "package.json", "index.d.ts", "LICENSE", "README.md")) {
        $s = Join-Path $src $item
        if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination $PluginDir -Recurse -Force }
      }
      $v = (Get-Content -LiteralPath (Join-Path $PluginDir "package.json") -Raw | ConvertFrom-Json).version
      Ok "vendored plugin v$v -> $PluginDir"
      Note "vendored plugin v$v"
    } else {
      Info "would vendor plugin from $src -> $PluginDir"
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  if ((-not $DryRun) -and (Test-Path -LiteralPath (Join-Path $PluginDir "dist\index.js"))) {
    if (Test-Path -LiteralPath $PatchScript) { & $PatchScript -PluginDir $PluginDir }
    else { Warn2 "missing patch script: $PatchScript" }
    $loadable = Test-PluginLoadable $PluginDir
    if ($loadable -eq $true) { Ok "plugin imports cleanly under Node" }
    elseif ($loadable -eq $false) { Warn2 "plugin failed to import under Node - check manually" }
  }
}

# ============================================================
Step 3 "Merge opencode config (instructions + plugin path)"
# ============================================================
$cfgPath = $null
foreach ($cand in @((Join-Path $OpencodeDir "opencode.jsonc"), (Join-Path $OpencodeDir "opencode.json"))) {
  if (Test-Path -LiteralPath $cand) { $cfgPath = $cand; break }
}
if (-not $cfgPath) { $cfgPath = Join-Path $OpencodeDir "opencode.jsonc" }

try {
  $cfg = [ordered]@{}
  if (Test-Path -LiteralPath $cfgPath) {
    Backup-File $cfgPath
    $cfg = ConvertTo-HashtableDeep (Read-Jsonc $cfgPath)
  }
  if (-not $cfg.Contains("`$schema")) { $cfg["`$schema"] = "https://opencode.ai/config.json" }

  # instructions
  $instr = @()
  if ($cfg.Contains("instructions")) { $instr = @($cfg["instructions"]) }
  $instr = $instr | Where-Object { $_ -and ($_ -notmatch '(?i)mem0') }
  if ($instr -notcontains $ProtocolPath) { $instr = @($instr) + $ProtocolPath }
  $cfg["instructions"] = @($instr)

  # plugin list: keep everything that is not mem0, put our path first
  $plugins = @()
  if ($cfg.Contains("plugin")) { $plugins = @($cfg["plugin"]) }
  $plugins = @($plugins | Where-Object { $_ -and ($_ -notmatch '(?i)mem0') })
  $plugins = @($PluginDir) + $plugins
  $cfg["plugin"] = $plugins

  # drop an mcp.mem0 leftover / empty mcp block
  if ($cfg.Contains("mcp")) {
    if ($null -eq $cfg["mcp"]) { $cfg.Remove("mcp") }
    elseif ($cfg["mcp"] -is [System.Collections.IDictionary]) {
      if ($cfg["mcp"].Keys.Count -eq 0) { $cfg.Remove("mcp") }
    }
  }

  if (-not $DryRun) {
    $ordered = [ordered]@{}
    foreach ($k in $cfg.Keys) { $ordered[$k] = $cfg[$k] }
    Write-Utf8NoBom $cfgPath ($ordered | ConvertTo-Json -Depth 40)
    Ok "merged instructions + plugin into $cfgPath"
    Note "updated opencode config"
  } else {
    Info "would merge into $cfgPath :"
    Info "  instructions += $ProtocolPath"
    Info "  plugin       += $PluginDir"
  }
} catch {
  Warn2 "config merge failed for ${cfgPath}: $($_.Exception.Message)"
  Warn2 "merge manually using files\opencode-mem0.snippet.jsonc"
}

# ============================================================
Step 4 "Verify"
# ============================================================
if (-not $DryRun) {
  $bootstrapped = Test-Path -LiteralPath (Join-Path $PluginDir "dist\index.js")
  if ($bootstrapped) {
    $t = [System.IO.File]::ReadAllText((Join-Path $PluginDir "dist\index.js"))
    if ($t.Contains("__createRequire(import.meta.url)")) { Ok "patch verified in dist/index.js" }
    else { Warn2 "patch marker not found - plugin may fail under the desktop app" }
  }
  $cli = Get-OpencodeCli
  if ($cli) {
    try {
      $resolved = & $cli debug config 2>$null | Out-String
      if ($resolved -match 'mem0-plugin') { Ok "opencode resolves the mem0-plugin path" } else { Warn2 "opencode config does not reference mem0-plugin" }
      if ($resolved -match 'mem0-remember') { Ok "mem0 skills/commands are registered" }
    } catch { Info "skipped 'opencode debug config' check" }
  }
}

# ============================================================
Step 5 "Done"
# ============================================================
Write-Host ""
if ($DryRun) {
  Write-Host "DRY RUN complete - nothing was written." -ForegroundColor Yellow
} else {
  Write-Host "Done. Scope pinned to user_id = 'opencode', app_id = 'opencode'." -ForegroundColor Green
  if ($script:BackedUp.Count -gt 0) { Write-Host "Backups: $BackupDir" }
  Write-Host ""
  Write-Host "NEXT: fully restart opencode (plugins load only at start)." -ForegroundColor Green
  Write-Host "Then verify:  run  /mem0-status   and ask it to remember + recall something." -ForegroundColor Green
  Write-Host "Cross-device: same MEM0_API_KEY + user_id/app_id 'opencode' on every machine." -ForegroundColor Green
}
