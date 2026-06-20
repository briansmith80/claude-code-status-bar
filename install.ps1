#Requires -Version 5.1
<#
.SYNOPSIS
  Claude Code Status Bar - Windows installer / updater.

.DESCRIPTION
  Downloads the status bar into ~\.claude and wires it into settings.json.
  Re-running it is always safe and is also the update mechanism.

  One-liner (PowerShell):
    irm https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main/install.ps1 | iex

.PARAMETER SourceDir
  Install from a local clone instead of downloading (used by CI and offline installs).

.PARAMETER TargetDir
  Install destination. Defaults to $env:USERPROFILE\.claude.
#>
param(
  [string]$SourceDir = '',
  [string]$TargetDir = (Join-Path $env:USERPROFILE '.claude')
)

$ErrorActionPreference = 'Stop'
$RepoRaw = 'https://raw.githubusercontent.com/briansmith80/claude-code-status-bar/main'

function Get-RepoFile {
  param([string]$Name, [string]$Dest)
  if ($SourceDir) {
    Copy-Item -Path (Join-Path $SourceDir $Name) -Destination $Dest -Force
  } else {
    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/$Name" -OutFile $Dest
  }
}

# Write JSON without a BOM: a UTF-8 BOM in settings.json breaks JSON parsers
function Write-NoBomFile {
  param([string]$Path, [string]$Content)
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

# ── Download files ────────────────────────────────────────────
$versionFile = Join-Path $TargetDir '.statusline-version'
Get-RepoFile -Name 'VERSION' -Dest $versionFile
$version = (Get-Content $versionFile -Raw).Trim()

$scriptPath = Join-Path $TargetDir 'statusline-command.sh'
if (Test-Path $scriptPath) {
  Write-Host "Updating claude-code-status-bar to v$version..."
} else {
  Write-Host "Installing claude-code-status-bar v$version..."
}

# Stage the runtime files, verify each against the release's SHA256SUMS, then
# move them into place - mirroring the runtime self-updater (security finding
# G1). This installer doubles as the documented update path, so it must not
# write a tampered / truncated download. On a checksum mismatch we abort leaving
# the install untouched; when the manifest is unavailable (older fork) the check
# is skipped gracefully. statusline-command.sh is required; the .js helpers are
# optional.
$runtimeFiles = @('statusline-command.sh', 'statusline-helper.js', 'statusline-subagent.js')
$stageDir = New-Item -ItemType Directory -Force -Path `
  (Join-Path ([System.IO.Path]::GetTempPath()) ("ccsb-install-" + [System.IO.Path]::GetRandomFileName()))
try {
  foreach ($f in $runtimeFiles) {
    try {
      Get-RepoFile -Name $f -Dest (Join-Path $stageDir $f)
    } catch {
      if ($f -eq 'statusline-command.sh') {
        throw "Failed to download $f - aborting (nothing installed). $($_.Exception.Message)"
      }
    }
  }

  $sumsPath = Join-Path $stageDir 'SHA256SUMS'
  $haveSums = $false
  try {
    Get-RepoFile -Name 'SHA256SUMS' -Dest $sumsPath
    $haveSums = (Test-Path $sumsPath) -and ((Get-Item $sumsPath).Length -gt 0)
  } catch { $haveSums = $false }

  if ($haveSums) {
    $expected = @{}
    foreach ($line in Get-Content $sumsPath) {
      $parts = $line.Trim() -split '\s+', 2
      if ($parts.Count -eq 2) {
        $name = Split-Path ($parts[1] -replace '^\*', '') -Leaf   # drop binary marker; basename
        $expected[$name] = $parts[0].ToLower()
      }
    }
    foreach ($f in $runtimeFiles) {
      $staged = Join-Path $stageDir $f
      if (-not (Test-Path $staged)) { continue }   # optional helper not downloaded
      $actual = (Get-FileHash -Path $staged -Algorithm SHA256).Hash.ToLower()
      if (-not $expected.ContainsKey($f) -or $expected[$f] -ne $actual) {
        throw "Checksum verification failed for $f - aborting (nothing installed)."
      }
    }
    Write-Host "  Integrity verified against SHA256SUMS."
  }

  # Verified (or skipped gracefully) - move staged files into place.
  Move-Item -Path (Join-Path $stageDir 'statusline-command.sh') -Destination $scriptPath -Force
  foreach ($helper in @('statusline-helper.js', 'statusline-subagent.js')) {
    $staged = Join-Path $stageDir $helper
    if (Test-Path $staged) { Move-Item -Path $staged -Destination (Join-Path $TargetDir $helper) -Force }
  }
} finally {
  Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  Files installed to: $TargetDir"
Write-Host "  Version: $version"

# ── Config template ───────────────────────────────────────────
# Ship a commented reference template (always refreshed) and create the live
# statusline.conf from it on first install ONLY - never overwrite an existing
# one (user config survives updates). Every line is commented, so a fresh copy
# changes nothing; it just makes the options discoverable and editable.
$confExample = Join-Path $TargetDir 'statusline.conf.example'
$confFile = Join-Path $TargetDir 'statusline.conf'
try { Get-RepoFile -Name 'statusline.conf.example' -Dest $confExample } catch { }
if ((Test-Path $confExample) -and -not (Test-Path $confFile)) {
  Copy-Item -Path $confExample -Destination $confFile -Force
  Write-Host "  Config created: $confFile (commented - edit to customise)"
} elseif (Test-Path $confFile) {
  Write-Host "  Config kept: $confFile (new options are in statusline.conf.example)"
}

# ── Runtime requirement: Git Bash ─────────────────────────────
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
  Write-Warning ("bash was not found on your PATH. The status bar runs via Git for Windows " +
    "(https://git-scm.com/download/win), which Claude Code on Windows requires anyway. " +
    "Install it, then restart your terminal.")
}

# ── Update settings.json ──────────────────────────────────────
# Forward slashes: Claude Code consumes backslashes in command paths.
# The paths are quoted so the commands survive profile dirs with spaces
# (e.g. C:/Users/John Smith) under every spawn shell (bash, PowerShell, cmd).
$fwdTarget = $TargetDir -replace '\\', '/'
$statusCmd = "bash `"$fwdTarget/statusline-command.sh`""
$subagentCmd = $null
if (Get-Command node -ErrorAction SilentlyContinue) {
  $subagentCmd = "node `"$fwdTarget/statusline-subagent.js`""
}

$settingsFile = Join-Path $TargetDir 'settings.json'
if (-not (Test-Path $settingsFile)) {
  $settings = [ordered]@{
    statusLine = [ordered]@{ type = 'command'; command = $statusCmd; refreshInterval = 60 }
  }
  if ($subagentCmd) {
    $settings['subagentStatusLine'] = [ordered]@{ type = 'command'; command = $subagentCmd }
  }
  Write-NoBomFile -Path $settingsFile -Content (($settings | ConvertTo-Json -Depth 5) + "`n")
  Write-Host "  Created settings: $settingsFile"
} else {
  try {
    $json = Get-Content $settingsFile -Raw | ConvertFrom-Json
    $added = @()
    if (-not $json.PSObject.Properties['statusLine']) {
      $json | Add-Member -NotePropertyName 'statusLine' `
        -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = $statusCmd; refreshInterval = 60 })
      $added += 'statusLine'
    }
    if ($subagentCmd -and -not $json.PSObject.Properties['subagentStatusLine']) {
      $json | Add-Member -NotePropertyName 'subagentStatusLine' `
        -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = $subagentCmd })
      $added += 'subagentStatusLine'
    }
    # Migrate commands written by older installs: MSYS-style paths (from
    # install.sh under Git Bash, e.g. "node /c/Users/...") fail when Claude
    # Code spawns the command via PowerShell or cmd, and unquoted paths break
    # on profile dirs with spaces. Rewrite only exact matches of our own old
    # commands; customised entries are never touched.
    $migrated = @()
    if ($TargetDir -match '^([A-Za-z]):[\\/](.*)$') {
      $msysTarget = '/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
      $oldForms = @{
        statusLine         = @("bash $msysTarget/statusline-command.sh", "bash $fwdTarget/statusline-command.sh")
        subagentStatusLine = @("node $msysTarget/statusline-subagent.js", "node $fwdTarget/statusline-subagent.js")
      }
      $freshCmds = @{ statusLine = $statusCmd; subagentStatusLine = $subagentCmd }
      foreach ($key in @('statusLine', 'subagentStatusLine')) {
        $entry = $json.PSObject.Properties[$key]
        if ($freshCmds[$key] -and $entry -and $oldForms[$key] -contains $entry.Value.command) {
          $entry.Value.command = $freshCmds[$key]
          $migrated += $key
        }
      }
    }
    # Older installs (pre-v2.10.1) created a statusLine block with no
    # refreshInterval, so the bar only refreshed on new messages (countdown
    # labels and the live activity line went stale while idle). Add the default
    # to an existing block that lacks one; a value the user set is never touched.
    $refreshAdded = $false
    $slProp = $json.PSObject.Properties['statusLine']
    if ($slProp -and $slProp.Value -and -not $slProp.Value.PSObject.Properties['refreshInterval']) {
      $slProp.Value | Add-Member -NotePropertyName 'refreshInterval' -NotePropertyValue 60
      $refreshAdded = $true
    }
    if ($added.Count -gt 0 -or $migrated.Count -gt 0 -or $refreshAdded) {
      Write-NoBomFile -Path $settingsFile -Content (($json | ConvertTo-Json -Depth 50) + "`n")
      if ($added.Count -gt 0) { Write-Host "  Updated settings ($($added -join ', ')): $settingsFile" }
      if ($migrated.Count -gt 0) { Write-Host "  Migrated to Windows-native quoted paths ($($migrated -join ', ')): $settingsFile" }
      if ($refreshAdded) { Write-Host "  Added statusLine.refreshInterval (60): $settingsFile" }
    } else {
      Write-Host "  settings.json already configured - skipped."
    }
  } catch {
    Write-Warning "Could not update settings.json automatically: $($_.Exception.Message)"
    Write-Host '  Add this to settings.json yourself:'
    Write-Host "    `"statusLine`": { `"type`": `"command`", `"command`": `"$statusCmd`", `"refreshInterval`": 60 }"
    if ($subagentCmd) {
      Write-Host "    `"subagentStatusLine`": { `"type`": `"command`", `"command`": `"$subagentCmd`" }"
    }
  }
}

# ── Clear update cache ────────────────────────────────────────
Remove-Item -Path (Join-Path $TargetDir '.statusline-update-cache') -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Done! Your status bar should appear automatically.'
