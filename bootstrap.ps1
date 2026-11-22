# First run on a fresh Shadow PC. From a normal (non-admin) PowerShell window:
#
#   irm https://raw.githubusercontent.com/kud/shadow-box-bootstrap/master/bootstrap.ps1 | iex
#
# It makes sure winget works, installs Git and PowerShell 7, clones this
# repository to %USERPROFILE%\shadow-box-bootstrap (or pulls it when it is
# already there) and runs `shadow install`. Safe to run again at any time.
#
# Written for Windows PowerShell 5.1, which is what a fresh Windows ships with.

# Wrapped in a script block so nothing leaks into the calling session.
& {
    $ErrorActionPreference = 'Stop'

    $repoUrl = 'https://github.com/kud/shadow-box-bootstrap.git'
    $target = if ($env:SHADOW_BOX_HOME) { $env:SHADOW_BOX_HOME } else { Join-Path $env:USERPROFILE 'shadow-box-bootstrap' }

    function Write-Bootstrap([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

    function Update-SessionPath {
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
    }

    function Install-IfMissing([string]$Id, [string]$Command) {
        if (Get-Command $Command -ErrorAction SilentlyContinue) {
            Write-Host "  [ok]   $Id"
            return
        }
        Write-Host "  [do]   installing $Id"
        winget install --id $Id --exact --source winget --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0 -and -not (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw "winget could not install $Id (exit code $LASTEXITCODE)"
        }
        Update-SessionPath
    }

    Write-Bootstrap 'winget'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        # On a first sign-in, App Installer is often present but not yet registered.
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
            Update-SessionPath
        }
        catch { Write-Verbose $_.Exception.Message }
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'winget is not available. Install "App Installer" from the Microsoft Store, then run this again:' -ForegroundColor Red
        Write-Host '  ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
        return
    }
    Write-Host '  [ok]   winget'

    Write-Bootstrap 'prerequisites'
    Install-IfMissing -Id 'Git.Git' -Command 'git'
    Install-IfMissing -Id 'Microsoft.PowerShell' -Command 'pwsh'

    Write-Bootstrap "repository in $target"
    if (Test-Path (Join-Path $target '.git')) {
        git -C $target pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-Host '  git pull failed; continuing with the local copy' -ForegroundColor Yellow }
    }
    else {
        git clone $repoUrl $target
        if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit code $LASTEXITCODE)" }
    }

    Write-Bootstrap 'shadow install'
    & (Join-Path $target 'shadow.cmd') install

    Write-Host ''
    Write-Host "Next time, update everything with:  $target\shadow update" -ForegroundColor Green
}
