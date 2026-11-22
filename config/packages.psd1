# Desired packages for the Shadow PC.
#
# Add a line, run `.\shadow update`, done. Remove a line and the package is
# simply no longer managed (it is not uninstalled).
#
# Winget entries
#   Id       exact winget identifier (find one with `winget search <name>`)
#   Name     label shown in the output
#   Upgrade  $false for apps that update themselves (game launchers), so
#            `update` leaves them alone; defaults to $true
#   Scope    'user' or 'machine' to force an install scope; omitted = winget default
#
# Scoop is the fallback for what winget does not carry. It is only installed
# when at least one Scoop app is listed below.

@{
    Winget = @(
        # Launcher
        @{ Id = 'Vicinae.Vicinae'; Name = 'Vicinae' }

        # Game launchers (they self-update, so `update` does not touch them)
        @{ Id = 'Valve.Steam';                   Name = 'Steam';               Upgrade = $false }
        @{ Id = 'EpicGames.EpicGamesLauncher';   Name = 'Epic Games Launcher'; Upgrade = $false }
        @{ Id = 'ElectronicArts.EADesktop';      Name = 'EA app';              Upgrade = $false }

        # Everyday tools
        @{ Id = 'Mozilla.Firefox';         Name = 'Firefox' }
        @{ Id = 'WinDirStat.WinDirStat';   Name = 'WinDirStat' }
        @{ Id = 'BleachBit.BleachBit';     Name = 'BleachBit' }

        # Development
        @{ Id = 'Git.Git';                 Name = 'Git' }
        @{ Id = 'Microsoft.PowerShell';    Name = 'PowerShell 7' }
        @{ Id = 'OpenJS.NodeJS.LTS';       Name = 'Node.js LTS' }

        # Optional, uncomment to enable
        # @{ Id = 'Microsoft.PowerToys';   Name = 'PowerToys' }
        # @{ Id = 'GOG.Galaxy';            Name = 'GOG Galaxy';     Upgrade = $false }
        # @{ Id = 'Ubisoft.Connect';       Name = 'Ubisoft Connect'; Upgrade = $false }
        # @{ Id = 'Discord.Discord';       Name = 'Discord';        Upgrade = $false }
    )

    Scoop = @{
        Buckets = @(
            # 'extras'
        )
        Apps = @(
            # 'extras/some-app'
        )
    }
}
