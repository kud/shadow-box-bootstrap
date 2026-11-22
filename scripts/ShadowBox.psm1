#Requires -Version 5.1
# Core logic for shadow-box-bootstrap. Every function is idempotent: running it
# twice leaves the machine exactly as running it once.

Set-StrictMode -Version 3.0

# winget exit codes (https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
$script:WingetUpdateNotApplicable = -1978335189 # 0x8A15002B: no newer version
$script:WingetAlreadyInstalled = -1978335135    # 0x8A150061

$script:ValidScopes = @('user', 'machine')
$script:IsWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:ValidRegistryTypes = @('DWord', 'QWord', 'String', 'ExpandString')

# --- output -----------------------------------------------------------------

function Write-ShadowStep([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-ShadowOk([string]$Message) { Write-Host "  [ok]   $Message" -ForegroundColor Green }
function Write-ShadowDo([string]$Message) { Write-Host "  [do]   $Message" -ForegroundColor Yellow }
function Write-ShadowSkip([string]$Message) { Write-Host "  [skip] $Message" -ForegroundColor DarkGray }
function Write-ShadowFail([string]$Message) { Write-Host "  [fail] $Message" -ForegroundColor Red }

# --- configuration ----------------------------------------------------------

function Get-ShadowConfigValue {
    # Reads a key from a hashtable, returning $Default when absent.
    param([hashtable]$Table, [string]$Key, $Default = $null)
    if ($Table.ContainsKey($Key)) { return $Table[$Key] }
    return $Default
}

function Test-ShadowConfig {
    <#
    .SYNOPSIS
        Returns a list of human-readable problems in the configuration (empty when valid).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Packages,
        [Parameter(Mandatory)][hashtable]$Settings
    )
    $problems = [System.Collections.Generic.List[string]]::new()

    $seen = @{}
    foreach ($pkg in @(Get-ShadowConfigValue $Packages 'Winget' @())) {
        if ($pkg -isnot [hashtable]) { $problems.Add('Winget: every entry must be a @{ ... } table'); continue }
        $id = Get-ShadowConfigValue $pkg 'Id'
        if ([string]::IsNullOrWhiteSpace($id)) { $problems.Add('Winget: an entry has no Id'); continue }
        if ($seen.ContainsKey($id)) { $problems.Add("Winget: '$id' is listed twice") }
        $seen[$id] = $true
        $upgrade = Get-ShadowConfigValue $pkg 'Upgrade' $true
        if ($upgrade -isnot [bool]) { $problems.Add("Winget: '$id' Upgrade must be `$true or `$false") }
        $scope = Get-ShadowConfigValue $pkg 'Scope'
        if ($null -ne $scope -and $script:ValidScopes -notcontains $scope) {
            $problems.Add("Winget: '$id' Scope must be one of: $($script:ValidScopes -join ', ')")
        }
        foreach ($key in $pkg.Keys) {
            if (@('Id', 'Name', 'Upgrade', 'Scope') -notcontains $key) { $problems.Add("Winget: '$id' has unknown key '$key'") }
        }
    }

    $scoop = Get-ShadowConfigValue $Packages 'Scoop' @{}
    if ($scoop -isnot [hashtable]) { $problems.Add('Scoop must be a @{ Buckets = @(); Apps = @() } table') }

    $names = @{}
    foreach ($tweak in @(Get-ShadowConfigValue $Settings 'Tweaks' @())) {
        if ($tweak -isnot [hashtable]) { $problems.Add('Tweaks: every entry must be a @{ ... } table'); continue }
        $name = Get-ShadowConfigValue $tweak 'Name'
        if ([string]::IsNullOrWhiteSpace($name)) { $problems.Add('Tweaks: an entry has no Name'); continue }
        if ($names.ContainsKey($name)) { $problems.Add("Tweaks: '$name' is listed twice") }
        $names[$name] = $true
        if ((Get-ShadowConfigValue $tweak 'Enabled' $false) -isnot [bool]) { $problems.Add("Tweaks: '$name' Enabled must be `$true or `$false") }
        $values = @(Get-ShadowConfigValue $tweak 'Values' @())
        if ($values.Count -eq 0) { $problems.Add("Tweaks: '$name' has no Values") }
        foreach ($v in $values) {
            if ($v -isnot [hashtable]) { $problems.Add("Tweaks: '$name' values must be @{ ... } tables"); continue }
            foreach ($key in 'Path', 'Name', 'Value', 'Type') {
                if (-not $v.ContainsKey($key)) { $problems.Add("Tweaks: '$name' value is missing '$key'") }
            }
            if ($v.ContainsKey('Path') -and -not ([string]$v.Path).StartsWith('HKCU:\')) {
                $problems.Add("Tweaks: '$name' may only write under HKCU:\ (got '$($v.Path)')")
            }
            if ($v.ContainsKey('Type') -and $script:ValidRegistryTypes -notcontains $v.Type) {
                $problems.Add("Tweaks: '$name' Type must be one of: $($script:ValidRegistryTypes -join ', ')")
            }
        }
    }

    return , $problems.ToArray()
}

function Import-ShadowConfig {
    <#
    .SYNOPSIS
        Loads config/packages.psd1 and config/settings.psd1 and validates them.
    #>
    param([Parameter(Mandatory)][string]$Root)
    $packages = Import-PowerShellDataFile -Path (Join-Path $Root 'config/packages.psd1')
    $settings = Import-PowerShellDataFile -Path (Join-Path $Root 'config/settings.psd1')
    $problems = Test-ShadowConfig -Packages $packages -Settings $settings
    if ($problems.Count -gt 0) {
        throw "Configuration problems:`n  - $($problems -join "`n  - ")"
    }
    return @{ Packages = $packages; Settings = $settings }
}

# --- environment ------------------------------------------------------------

function Update-ShadowSessionPath {
    # Picks up PATH entries added by installers without opening a new shell.
    if (-not $script:IsWindowsPlatform) { return }
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Test-ShadowElevated {
    if (-not $script:IsWindowsPlatform) { return $false }
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- winget -----------------------------------------------------------------

function Invoke-Winget {
    # Thin wrapper so tests can mock winget; returns the exit code.
    param([string[]]$Arguments)
    & winget @Arguments | Out-Host
    return $LASTEXITCODE
}

function Test-WingetPackage {
    param([Parameter(Mandatory)][string]$Id)
    & winget list --id $Id --exact --accept-source-agreements --disable-interactivity *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-WingetCommonArgs([hashtable]$Package) {
    $wingetArgs = @('--id', $Package.Id, '--exact', '--source', 'winget', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    $scope = Get-ShadowConfigValue $Package 'Scope'
    if ($scope) { $wingetArgs += @('--scope', $scope) }
    return $wingetArgs
}

function Install-ShadowWingetPackage {
    <#
    .SYNOPSIS
        Installs a winget package when missing. Returns 'present', 'installed', 'planned' or 'failed'.
    #>
    param([Parameter(Mandatory)][hashtable]$Package, [switch]$DryRun)
    $label = Get-ShadowConfigValue $Package 'Name' $Package.Id
    if (Test-WingetPackage -Id $Package.Id) {
        Write-ShadowOk "$label"
        return 'present'
    }
    if ($DryRun) {
        Write-ShadowDo "would install $label ($($Package.Id))"
        return 'planned'
    }
    Write-ShadowDo "installing $label ($($Package.Id))"
    $code = Invoke-Winget -Arguments (@('install') + (Get-WingetCommonArgs $Package))
    if ($code -eq 0 -or $code -eq $script:WingetAlreadyInstalled) { return 'installed' }
    Write-ShadowFail "${label}: winget exited with $code"
    return 'failed'
}

function Update-ShadowWingetPackage {
    <#
    .SYNOPSIS
        Upgrades an installed winget package unless it opts out with Upgrade = $false.
        Returns 'skipped', 'current', 'upgraded', 'planned' or 'failed'.
    #>
    param([Parameter(Mandatory)][hashtable]$Package, [switch]$DryRun)
    $label = Get-ShadowConfigValue $Package 'Name' $Package.Id
    if (-not (Get-ShadowConfigValue $Package 'Upgrade' $true)) {
        Write-ShadowSkip "$label updates itself"
        return 'skipped'
    }
    if ($DryRun) {
        Write-ShadowDo "would upgrade $label if a newer version exists"
        return 'planned'
    }
    $code = Invoke-Winget -Arguments (@('upgrade') + (Get-WingetCommonArgs $Package))
    if ($code -eq 0) { Write-ShadowOk "$label upgraded or current"; return 'upgraded' }
    if ($code -eq $script:WingetUpdateNotApplicable) { Write-ShadowOk "$label is current"; return 'current' }
    Write-ShadowFail "${label}: winget exited with $code"
    return 'failed'
}

# --- scoop ------------------------------------------------------------------

function Install-ShadowScoop {
    param([switch]$DryRun)
    if (Get-Command scoop -ErrorAction SilentlyContinue) { Write-ShadowOk 'Scoop'; return 'present' }
    if ($DryRun) { Write-ShadowDo 'would install Scoop'; return 'planned' }
    Write-ShadowDo 'installing Scoop'
    $installer = Join-Path ([IO.Path]::GetTempPath()) 'install-scoop.ps1'
    Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $installer
    if (Test-ShadowElevated) { & $installer -RunAsAdmin | Out-Host } else { & $installer | Out-Host }
    Update-ShadowSessionPath
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return 'installed' }
    Write-ShadowFail 'Scoop did not install'
    return 'failed'
}

function Sync-ShadowScoop {
    <#
    .SYNOPSIS
        Adds missing buckets and apps; with -Upgrade also updates everything Scoop manages.
        Returns the number of failures.
    #>
    param([Parameter(Mandatory)][hashtable]$Scoop, [switch]$Upgrade, [switch]$DryRun)
    $buckets = @(Get-ShadowConfigValue $Scoop 'Buckets' @())
    $apps = @(Get-ShadowConfigValue $Scoop 'Apps' @())
    if ($apps.Count -eq 0) { Write-ShadowSkip 'no Scoop apps listed'; return 0 }

    $failures = 0
    $state = Install-ShadowScoop -DryRun:$DryRun
    if ($state -eq 'failed') { return 1 }
    if ($state -eq 'planned') {
        foreach ($app in $apps) { Write-ShadowDo "would install $app" }
        return 0
    }

    $known = @(scoop bucket list | ForEach-Object { $_.Name })
    foreach ($bucket in $buckets) {
        if ($known -contains $bucket) { Write-ShadowOk "bucket $bucket"; continue }
        if ($DryRun) { Write-ShadowDo "would add bucket $bucket"; continue }
        Write-ShadowDo "adding bucket $bucket"
        scoop bucket add $bucket | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-ShadowFail "bucket $bucket"; $failures++ }
    }

    foreach ($app in $apps) {
        $short = ($app -split '/')[-1]
        scoop prefix $short *> $null
        if ($LASTEXITCODE -eq 0) { Write-ShadowOk $app; continue }
        if ($DryRun) { Write-ShadowDo "would install $app"; continue }
        Write-ShadowDo "installing $app"
        scoop install $app | Out-Host
        if ($LASTEXITCODE -ne 0) { Write-ShadowFail $app; $failures++ }
    }

    if ($Upgrade) {
        if ($DryRun) { Write-ShadowDo 'would run scoop update *' }
        else {
            scoop update | Out-Host
            scoop update '*' | Out-Host
            if ($LASTEXITCODE -ne 0) { Write-ShadowFail 'scoop update'; $failures++ }
        }
    }
    return $failures
}

# --- registry tweaks --------------------------------------------------------

function Test-ShadowRegistryValue {
    param([Parameter(Mandatory)][hashtable]$Entry)
    if (-not (Test-Path -LiteralPath $Entry.Path)) { return $false }
    $item = Get-ItemProperty -LiteralPath $Entry.Path -Name $Entry.Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    return ([string]$item.($Entry.Name) -eq [string]$Entry.Value)
}

function Set-ShadowTweak {
    <#
    .SYNOPSIS
        Applies one enabled tweak. Returns 'disabled', 'present', 'applied', 'planned' or 'failed'.
    #>
    param([Parameter(Mandatory)][hashtable]$Tweak, [switch]$DryRun)
    if (-not (Get-ShadowConfigValue $Tweak 'Enabled' $false)) {
        Write-ShadowSkip "$($Tweak.Name) (opt-in, disabled)"
        return 'disabled'
    }
    $pending = @($Tweak.Values | Where-Object { -not (Test-ShadowRegistryValue -Entry $_) })
    if ($pending.Count -eq 0) { Write-ShadowOk $Tweak.Name; return 'present' }
    if ($DryRun) { Write-ShadowDo "would apply $($Tweak.Name): $($Tweak.Description)"; return 'planned' }
    try {
        foreach ($entry in $pending) {
            if (-not (Test-Path -LiteralPath $entry.Path)) { New-Item -Path $entry.Path -Force | Out-Null }
            New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -Value $entry.Value `
                -PropertyType $entry.Type -Force | Out-Null
        }
        Write-ShadowDo "applied $($Tweak.Name)"
        return 'applied'
    }
    catch {
        Write-ShadowFail "$($Tweak.Name): $($_.Exception.Message)"
        return 'failed'
    }
}

# --- orchestration ----------------------------------------------------------

function Invoke-ShadowSync {
    <#
    .SYNOPSIS
        Brings the machine to the state described in config/. Returns the number of failures.
    .PARAMETER Upgrade
        Also upgrade packages that are already installed (the `update` command).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$Upgrade,
        [switch]$DryRun
    )
    $failures = 0

    Write-ShadowStep 'winget packages'
    if (-not $DryRun) { Invoke-Winget -Arguments @('source', 'update', '--disable-interactivity') | Out-Null }
    foreach ($pkg in @($Config.Packages.Winget)) {
        $state = Install-ShadowWingetPackage -Package $pkg -DryRun:$DryRun
        if ($state -eq 'failed') { $failures++; continue }
        if ($Upgrade -and $state -eq 'present') {
            if ((Update-ShadowWingetPackage -Package $pkg -DryRun:$DryRun) -eq 'failed') { $failures++ }
        }
    }
    Update-ShadowSessionPath

    Write-ShadowStep 'Scoop (fallback)'
    $failures += Sync-ShadowScoop -Scoop (Get-ShadowConfigValue $Config.Packages 'Scoop' @{}) -Upgrade:$Upgrade -DryRun:$DryRun

    Write-ShadowStep 'Windows settings (opt-in)'
    foreach ($tweak in @(Get-ShadowConfigValue $Config.Settings 'Tweaks' @())) {
        if ((Set-ShadowTweak -Tweak $tweak -DryRun:$DryRun) -eq 'failed') { $failures++ }
    }

    return $failures
}

function Show-ShadowStatus {
    param([Parameter(Mandatory)][hashtable]$Config)
    Write-ShadowStep 'winget packages'
    foreach ($pkg in @($Config.Packages.Winget)) {
        $label = Get-ShadowConfigValue $pkg 'Name' $pkg.Id
        if (Test-WingetPackage -Id $pkg.Id) { Write-ShadowOk $label } else { Write-ShadowDo "$label is missing" }
    }
    Write-ShadowStep 'Scoop apps'
    $apps = @(Get-ShadowConfigValue (Get-ShadowConfigValue $Config.Packages 'Scoop' @{}) 'Apps' @())
    if ($apps.Count -eq 0) { Write-ShadowSkip 'none listed' }
    elseif (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { Write-ShadowDo 'Scoop is not installed' }
    else {
        foreach ($app in $apps) {
            scoop prefix (($app -split '/')[-1]) *> $null
            if ($LASTEXITCODE -eq 0) { Write-ShadowOk $app } else { Write-ShadowDo "$app is missing" }
        }
    }
    Write-ShadowStep 'Windows settings (opt-in)'
    foreach ($tweak in @(Get-ShadowConfigValue $Config.Settings 'Tweaks' @())) {
        if (-not $tweak.Enabled) { Write-ShadowSkip "$($tweak.Name) (disabled)"; continue }
        $pending = @($tweak.Values | Where-Object { -not (Test-ShadowRegistryValue -Entry $_) })
        if ($pending.Count -eq 0) { Write-ShadowOk $tweak.Name } else { Write-ShadowDo "$($tweak.Name) is not applied yet" }
    }
}

Export-ModuleMember -Function Test-ShadowConfig, Import-ShadowConfig, Update-ShadowSessionPath, `
    Test-ShadowElevated, Invoke-Winget, Test-WingetPackage, Install-ShadowWingetPackage, `
    Update-ShadowWingetPackage, Install-ShadowScoop, Sync-ShadowScoop, Test-ShadowRegistryValue, `
    Set-ShadowTweak, Invoke-ShadowSync, Show-ShadowStatus, `
    Write-ShadowStep, Write-ShadowOk, Write-ShadowDo, Write-ShadowSkip, Write-ShadowFail
