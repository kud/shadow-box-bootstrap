# Shadow Box Bootstrap

Automated setup for your Windows shadow box environment.

## Prerequisites

- Windows 10/11
- Administrator privileges

## Quick Start

### 1. Install Chocolatey Package Manager

Run this command in an elevated PowerShell window:

```powershell
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
```

### 2. Install Essential Applications

```powershell
choco install git.install nodejs.install steam origin epicgameslauncher windirstat firefox bleachbit geforce-experience
```
