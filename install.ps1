<#
  mem0-opencode-setup  (Windows)

  Installs the standard mem0 automatic-memory system for opencode:
    - opencode config: mem0 MCP server + memory-protocol instructions
    - <config>/memory-protocol.md
    - <config>/plugins/mem0-memory.js

  STEP 0 (before everything): detect and remove any OTHER mem0 integrations/configs
  on this machine, so all devices end up on one identical setup (user_id = "opencode").
  Everything it touches is backed up first.

  Usage (from a normal PowerShell):
    powershell -ExecutionPolicy Bypass -File install.ps1                 # apply
    powershell -ExecutionPolicy Bypass -File install.ps1 -DryRun         # preview only
    powershell -ExecutionPolicy Bypass -File install.ps1 -ApiKey "m0-..."# also store MEM0_API_KEY
    powershell -ExecutionPolicy Bypass -File install.ps1 -SkipCleanup    # do not touch other configs
#>
param(
  [switch]$DryRun,
  [switch]$SkipCleanup,
  [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"
$script:BackedUp = @{}

$UserHome    = $env:USERPROFILE
$OpencodeDir = Join-Path $UserHome ".config\opencode"
$PluginsDir  = Join-Path $OpencodeDir "plugins"
$ProtocolPath = Join-Path $OpencodeDir "memory-protocol.md"
$PluginPath   = Join-Path $PluginsDir "mem0-memory.js"
$Stamp        = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir    = Join-Path $OpencodeDir "mem0-setup-backup\$Stamp"
$PackageDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$FilesDir     = Join-Path $PackageDir "files"

function Step($n, $t) { Write-Host ""; Write-Host "== [$n] $t" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   + $m" -ForegroundColor Green }
function Warn2($m){ Write-Host "   ! $m" -ForegroundColor Yellow }
function Info($m) { Write-Host "   - $m" }

function Write-Utf8NoBom([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Backup-File([string]$path) {
  if (-not (Test-Path $path)) { return }
  if ($DryRun) { Info "would back up: $path"; return }
  $rel = $path.Substring($UserHome.Length).TrimStart('\','/') -replace '[\\/]', "__"
  if ($script:BackedUp.ContainsKey($rel)) { return }
  $script:BackedUp[$rel] = $true
  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  Copy-Item -LiteralPath $path -Destination (Join-Path $BackupDir $rel) -Force
  Ok "backed up -> $rel"
}

# ---------- JSONC helpers ----------
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
    if ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i+1] -eq '/') {
      while ($i -lt $text.Length -and $text[$i] -ne "`n") { $i++ }
      continue
    }
    if ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i+1] -eq '*') {
      $i += 2
      while ($i + 1 -lt $text.Length -and -not ($text[$i] -eq '*' -and $text[$i+1] -eq '/')) { $i++ }
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

# ---------- Targets ----------
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
$ScanDirs = @(
  (Join-Path $OpencodeDir "plugins"),
  (Join-Path $OpencodeDir "skill"),
  (Join-Path $OpencodeDir "skills"),
  (Join-Path $UserHome ".claude\skills"),
  (Join-Path $UserHome ".agents\skills")
)
# Never touch our own artifacts / this package.
$Exclude = @($ProtocolPath, $PluginPath, (Join-Path $OpencodeDir "skills\mem0-opencode-setup"))

function Is-Excluded([string]$path) {
  foreach ($e in $Exclude) { if ($path.StartsWith($e, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
  return $false
}

# ============================================================
Step 0 "Detect and remove other mem0 integrations / configs"
# ============================================================
$found = $false

if (-not $SkipCleanup) {
  foreach ($f in $JsonTargets) {
    if (-not (Test-Path $f)) { continue }
    if (Is-Excluded $f) { continue }
    $raw = Get-Content -LiteralPath $f -Raw
    if ($raw -notmatch '(?i)mem0') { continue }
    $found = $true
    Warn2 "mem0 reference in JSON config: $f"
    try {
      $obj = Read-Jsonc $f
      $cleaned = Clean-Mem0 $obj
      Backup-File $f
      if (-not $DryRun) {
        Write-Utf8NoBom $f (($cleaned | ConvertTo-Json -Depth 40))
        Ok "removed mem0 entries from $f"
      }
    } catch {
      Warn2 "could not parse $f (left untouched): $($_.Exception.Message)"
    }
  }

  foreach ($f in $TomlTargets) {
    if (-not (Test-Path $f)) { continue }
    if (Is-Excluded $f) { continue }
    $lines = Get-Content -LiteralPath $f
    if (($lines -join "`n") -notmatch '(?i)mem0') { continue }
    $found = $true
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
      Write-Utf8NoBom $f (($out -join "`r`n"))
      Ok "removed mem0 sections from $f"
    }
  }

  foreach ($d in $ScanDirs) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $p = $_.FullName
      if (Is-Excluded $p) { return }
      if ($_.Length -gt 2MB) { return }
      try {
        $c = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
      } catch { return }
      if ($c -match '(?i)mem0') {
        $found = $true
        Warn2 "mem0 reference in file: $p"
        Backup-File $p
        if (-not $DryRun) {
          Remove-Item -LiteralPath $p -Force
          Ok "removed $p"
        }
      }
    }
  }

  if (-not $found) { Ok "no other mem0 integrations found" }
} else {
  Info "cleanup skipped (-SkipCleanup)"
}

# ============================================================
Step 1 "Install standard files"
# ============================================================
if (-not (Test-Path $OpencodeDir)) { New-Item -ItemType Directory -Force -Path $OpencodeDir | Out-Null }
if (-not (Test-Path $PluginsDir))  { New-Item -ItemType Directory -Force -Path $PluginsDir  | Out-Null }

foreach ($pair in @(
  @{ src = (Join-Path $FilesDir "memory-protocol.md"); dst = $ProtocolPath },
  @{ src = (Join-Path $FilesDir "mem0-memory.js");     dst = $PluginPath }
)) {
  if (-not (Test-Path $pair.src)) { Warn2 "missing package file: $($pair.src)"; continue }
  if (Test-Path $pair.dst) { Backup-File $pair.dst }
  if (-not $DryRun) {
    Copy-Item -LiteralPath $pair.src -Destination $pair.dst -Force
    Ok "installed $($pair.dst)"
  } else {
    Info "would install $($pair.dst)"
  }
}

# ============================================================
Step 2 "Merge opencode config (mem0 MCP + memory-protocol instructions)"
# ============================================================
$cfgPath = $null
foreach ($cand in @((Join-Path $OpencodeDir "opencode.jsonc"), (Join-Path $OpencodeDir "opencode.json"))) {
  if (Test-Path $cand) { $cfgPath = $cand; break }
}
if (-not $cfgPath) { $cfgPath = Join-Path $OpencodeDir "opencode.jsonc" }

try {
  $cfg = [ordered]@{}
  if (Test-Path $cfgPath) {
    Backup-File $cfgPath
    $cfg = ConvertTo-HashtableDeep (Read-Jsonc $cfgPath)
  }
  if (-not $cfg.Contains("$schema")) { $cfg["`$schema"] = "https://opencode.ai/config.json" }

  $instr = @()
  if ($cfg.Contains("instructions")) { $instr = @($cfg["instructions"]) }
  if ($instr -notcontains $ProtocolPath) { $instr += $ProtocolPath }
  $cfg["instructions"] = $instr

  if (-not $cfg.Contains("mcp") -or $null -eq $cfg["mcp"]) { $cfg["mcp"] = [ordered]@{} }
  $cfg["mcp"]["mem0"] = [ordered]@{
    type    = "remote"
    url     = "https://mcp.mem0.ai/mcp"
    enabled = $true
    headers = [ordered]@{ Authorization = "Bearer {env:MEM0_API_KEY}" }
  }

  if (-not $DryRun) {
    Write-Utf8NoBom $cfgPath (($cfg | ConvertTo-Json -Depth 40))
    Ok "merged mem0 MCP + instructions into $cfgPath"
  } else {
    Info "would merge mem0 MCP + instructions into $cfgPath"
  }
} catch {
  Warn2 "config merge failed for ${cfgPath}: $($_.Exception.Message)"
  Warn2 "merge manually using files\opencode-mem0.snippet.jsonc"
}

# ============================================================
Step 3 "MEM0_API_KEY"
# ============================================================
if ($ApiKey -and $ApiKey.Trim().Length -gt 0) {
  if (-not $DryRun) {
    [Environment]::SetEnvironmentVariable("MEM0_API_KEY", $ApiKey.Trim(), "User")
    Ok "stored MEM0_API_KEY in the user environment"
  } else { Info "would store MEM0_API_KEY in the user environment" }
} else {
  $existing = [Environment]::GetEnvironmentVariable("MEM0_API_KEY", "User")
  if ($existing) { Ok "MEM0_API_KEY already set (user env)" }
  else { Warn2 "MEM0_API_KEY not set. Re-run with -ApiKey `"m0-...`" or run:  setx MEM0_API_KEY `"m0-...`"" }
}

# ============================================================
Step 4 "Done"
# ============================================================
Write-Host ""
if ($DryRun) { Write-Host "DRY RUN complete - nothing was written." -ForegroundColor Yellow }
else {
  Write-Host "Done. Scope pinned to user_id = 'opencode'." -ForegroundColor Green
  if ($found) { Write-Host "Backups: $BackupDir" }
  Write-Host "RESTART opencode for changes to take effect." -ForegroundColor Green
}
