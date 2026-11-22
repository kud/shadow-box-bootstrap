# Opt-in Windows settings.
#
# Every tweak ships disabled: nothing here changes Windows until you set
# `Enabled = $true` and run `.\shadow update`. All of them write to the current
# user's registry hive (HKCU) only, so none needs administrator rights, and
# each one is re-applied only when the value differs.
#
# Turning a tweak back to $false does not revert it; set the value by hand
# (or through Windows Settings) if you change your mind.
#
# Value types: DWord, String, QWord, ExpandString.

@{
    Tweaks = @(
        @{
            Name        = 'show-file-extensions'
            Description = 'Show file extensions in File Explorer'
            Enabled     = $false
            Values      = @(
                @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = 0; Type = 'DWord' }
            )
        }
        @{
            Name        = 'dark-mode'
            Description = 'Dark theme for apps and the system'
            Enabled     = $false
            Values      = @(
                @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme';   Value = 0; Type = 'DWord' }
                @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Value = 0; Type = 'DWord' }
            )
        }
        @{
            Name        = 'game-mode'
            Description = 'Make sure Windows Game Mode is on (it is by default)'
            Enabled     = $false
            Values      = @(
                @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1; Type = 'DWord' }
            )
        }
        @{
            Name        = 'no-background-recording'
            Description = 'Turn off Xbox Game Bar background recording (Game DVR)'
            Enabled     = $false
            Values      = @(
                @{ Path = 'HKCU:\System\GameConfigStore';                                 Name = 'GameDVR_Enabled';   Value = 0; Type = 'DWord' }
                @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR';      Name = 'AppCaptureEnabled'; Value = 0; Type = 'DWord' }
            )
        }
        @{
            Name        = 'raw-mouse-input'
            Description = 'Turn off "Enhance pointer precision" (mouse acceleration); applies after signing out'
            Enabled     = $false
            Values      = @(
                @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed';      Value = '0'; Type = 'String' }
                @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Value = '0'; Type = 'String' }
                @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Value = '0'; Type = 'String' }
            )
        }
    )
}
