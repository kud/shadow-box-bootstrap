#Requires -Version 5.1
<#
.SYNOPSIS
    Keeps the Shadow PC in the state described by config/.
.DESCRIPTION
    install  install everything missing and apply enabled settings
    update   pull the latest version of this repository, then install what is
             missing, upgrade what is outdated and apply enabled settings
    status   show what is installed, missing or not applied, changing nothing
    check    validate config/ files only
.EXAMPLE
    .\shadow update
.EXAMPLE
    .\shadow install -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'update', 'status', 'check', 'help')]
    [string]$Command = 'help',

    # Show what would happen without changing anything.
    [switch]$DryRun,

    # Internal: set when the script re-launches itself after a `git pull`.
    [switch]$NoPull
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'ShadowBox.psm1') -Force

function Show-Help {
    Write-Host @'
shadow-box-bootstrap

  .\shadow install   install everything listed in config\
  .\shadow update    pull this repo, then install, upgrade and apply settings
  .\shadow status    show what is missing, change nothing
  .\shadow check     validate config\ files

  Add -DryRun to install or update to preview without changing anything.
  Desired state lives in config\packages.psd1 and config\settings.psd1.
'@
}

function Update-ShadowRepository {
    # Fast-forwards this clone; returns $true when new commits arrived.
    param([switch]$Skip)
    if ($Skip) { return $false }
    if (-not (Test-Path (Join-Path $root '.git'))) {
        Write-ShadowSkip 'not a git clone, skipping self-update'
        return $false
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ShadowSkip 'git not found, skipping self-update'
        return $false
    }
    Write-ShadowStep 'self-update'
    $before = git -C $root rev-parse HEAD
    git -C $root pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-ShadowFail 'git pull failed (local changes?); continuing with the current version'
        return $false
    }
    $after = git -C $root rev-parse HEAD
    if ($before -eq $after) { Write-ShadowOk 'already up to date'; return $false }
    Write-ShadowDo "updated $($before.Substring(0, 7)) -> $($after.Substring(0, 7))"
    return $true
}

if ($Command -eq 'help') { Show-Help; exit 0 }

$config = Import-ShadowConfig -Root $root
if ($Command -eq 'check') {
    Write-ShadowOk 'config/ is valid'
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-ShadowFail 'winget was not found. Install "App Installer" from the Microsoft Store, then run this again.'
    exit 1
}

if ($Command -eq 'status') { Show-ShadowStatus -Config $config; exit 0 }

if ($Command -eq 'update' -and (Update-ShadowRepository -Skip:($DryRun -or $NoPull))) {
    # Re-run with the freshly pulled code and config.
    $shell = (Get-Process -Id $PID).Path
    & $shell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath update -NoPull
    exit $LASTEXITCODE
}

$logDir = Join-Path $env:LOCALAPPDATA 'shadow-box-bootstrap\logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir ("{0:yyyy-MM-dd_HHmmss}-{1}.log" -f (Get-Date), $Command)
Start-Transcript -Path $log | Out-Null
try {
    if ($DryRun) { Write-Host 'Dry run: nothing will be changed.' -ForegroundColor Magenta }
    $failures = Invoke-ShadowSync -Config $config -Upgrade:($Command -eq 'update') -DryRun:$DryRun
}
finally {
    Stop-Transcript | Out-Null
}

Write-Host ''
if ($failures -gt 0) {
    Write-ShadowFail "$failures step(s) failed. Log: $log"
    exit 1
}
Write-ShadowOk "done. Log: $log"
