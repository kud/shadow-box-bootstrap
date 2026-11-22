# Shadow Box Bootstrap

One command to set up a Windows [Shadow](https://shadow.tech) PC for gaming, one command to keep it up to date. The machine's desired state lives in two plain files under `config/`; the scripts make Windows match them and can be re-run at any time.

## First run on a fresh Shadow

Open **PowerShell** (no need for administrator) and paste:

```powershell
irm https://raw.githubusercontent.com/kud/shadow-box-bootstrap/master/bootstrap.ps1 | iex
```

This makes sure `winget` works, installs Git and PowerShell 7, clones this repository to `%USERPROFILE%\shadow-box-bootstrap` and runs `shadow install`. Installers that need administrator rights raise their own Windows prompt.

## Keeping it up to date

```powershell
~\shadow-box-bootstrap\shadow update
```

`update` pulls the latest version of this repository, installs anything newly listed, upgrades what is outdated (game launchers are left to update themselves) and applies any settings you turned on.

| Command          | Does                                                    |
| ---------------- | ------------------------------------------------------- |
| `shadow install` | install everything missing, apply enabled settings       |
| `shadow update`  | pull this repo, then install, upgrade, apply settings    |
| `shadow status`  | show what is missing or not applied, change nothing      |
| `shadow check`   | validate the `config/` files                             |

Add `-DryRun` to `install` or `update` to preview without changing anything. Each run writes a log to `%LOCALAPPDATA%\shadow-box-bootstrap\logs`.

## Adding a package

Find its winget id, then add one line to [`config/packages.psd1`](config/packages.psd1):

```powershell
winget search discord          # -> Discord.Discord
```

```powershell
@{ Id = 'Discord.Discord'; Name = 'Discord'; Upgrade = $false }
```

`Upgrade = $false` is for apps that update themselves. For software winget does not carry, list it under `Scoop`; Scoop is installed automatically the first time it is needed. Removing a line stops managing the package; it does not uninstall it.

## What gets installed

- **Launcher:** [Vicinae](https://vicinae.com), an open-source, Raycast-compatible launcher.
- **Games:** Steam, Epic Games Launcher, EA app.
- **Tools:** Firefox, WinDirStat, BleachBit.
- **Development:** Git, PowerShell 7, Node.js LTS.

PowerToys, GOG Galaxy, Ubisoft Connect and Discord are listed but commented out.

## Windows settings (opt-in)

[`config/settings.psd1`](config/settings.psd1) holds a few gaming-oriented tweaks: file extensions, dark mode, Game Mode, no Game Bar background recording, raw mouse input. **All ship disabled.** Set `Enabled = $true` on the ones you want and run `shadow update`. They only touch the current user's registry (`HKCU`) and are re-applied only when the value differs.

## GPU drivers

Not managed here. Shadow's Windows image is generally provisioned with its GPU driver, and replacing it by hand can do more harm than good on a cloud machine. NVIDIA retired GeForce Experience in favour of the NVIDIA app, which winget does not carry; install it from nvidia.com if you want it.

## Development

```powershell
Invoke-Pester ./tests                                                    # tests
Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
./scripts/shadow.ps1 check                                               # config validation
```

## Licence

[MIT](LICENSE)
