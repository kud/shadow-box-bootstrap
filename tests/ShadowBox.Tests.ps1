#Requires -Modules Pester
# Run with:  Invoke-Pester ./tests

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $root 'scripts/ShadowBox.psm1') -Force
    $packages = Import-PowerShellDataFile (Join-Path $root 'config/packages.psd1')
    $settings = Import-PowerShellDataFile (Join-Path $root 'config/settings.psd1')
}

Describe 'shipped configuration' {
    It 'is valid' {
        Test-ShadowConfig -Packages $packages -Settings $settings | Should -BeNullOrEmpty
    }

    It 'loads through Import-ShadowConfig' {
        { Import-ShadowConfig -Root $root } | Should -Not -Throw
    }

    It 'installs the Vicinae launcher' {
        $packages.Winget.Id | Should -Contain 'Vicinae.Vicinae'
    }

    It 'ships every Windows tweak disabled' {
        $settings.Tweaks | ForEach-Object { $_.Enabled | Should -BeFalse -Because $_.Name }
    }
}

Describe 'Test-ShadowConfig' {
    BeforeAll {
        $okSettings = @{ Tweaks = @() }
        $okPackages = @{ Winget = @() }
    }

    It 'rejects a duplicate winget id' {
        $p = @{ Winget = @(@{ Id = 'A.B' }, @{ Id = 'A.B' }) }
        (Test-ShadowConfig -Packages $p -Settings $okSettings) -join "`n" | Should -Match 'listed twice'
    }

    It 'rejects an entry without Id' {
        $p = @{ Winget = @(@{ Name = 'x' }) }
        (Test-ShadowConfig -Packages $p -Settings $okSettings) -join "`n" | Should -Match 'no Id'
    }

    It 'rejects an unknown key (typo guard)' {
        $p = @{ Winget = @(@{ Id = 'A.B'; Upgarde = $false }) }
        (Test-ShadowConfig -Packages $p -Settings $okSettings) -join "`n" | Should -Match "unknown key 'Upgarde'"
    }

    It 'rejects an invalid scope' {
        $p = @{ Winget = @(@{ Id = 'A.B'; Scope = 'everyone' }) }
        (Test-ShadowConfig -Packages $p -Settings $okSettings) -join "`n" | Should -Match 'Scope'
    }

    It 'refuses tweaks outside HKCU' {
        $s = @{ Tweaks = @(@{ Name = 't'; Enabled = $false; Values = @(@{ Path = 'HKLM:\Software\X'; Name = 'n'; Value = 1; Type = 'DWord' }) }) }
        (Test-ShadowConfig -Packages $okPackages -Settings $s) -join "`n" | Should -Match 'HKCU'
    }

    It 'rejects an unknown registry type' {
        $s = @{ Tweaks = @(@{ Name = 't'; Enabled = $false; Values = @(@{ Path = 'HKCU:\X'; Name = 'n'; Value = 1; Type = 'Binary' }) }) }
        (Test-ShadowConfig -Packages $okPackages -Settings $s) -join "`n" | Should -Match 'Type'
    }
}

Describe 'Install-ShadowWingetPackage' {
    It 'does nothing when the package is present' {
        Mock -ModuleName ShadowBox Test-WingetPackage { $true }
        Mock -ModuleName ShadowBox Invoke-Winget { 0 }
        Install-ShadowWingetPackage -Package @{ Id = 'A.B' } | Should -Be 'present'
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 0
    }

    It 'installs a missing package' {
        Mock -ModuleName ShadowBox Test-WingetPackage { $false }
        Mock -ModuleName ShadowBox Invoke-Winget { 0 }
        Install-ShadowWingetPackage -Package @{ Id = 'A.B'; Scope = 'user' } | Should -Be 'installed'
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 1 -ParameterFilter {
            $Arguments[0] -eq 'install' -and $Arguments -contains 'A.B' -and $Arguments -contains 'user'
        }
    }

    It 'only plans in dry-run mode' {
        Mock -ModuleName ShadowBox Test-WingetPackage { $false }
        Mock -ModuleName ShadowBox Invoke-Winget { 0 }
        Install-ShadowWingetPackage -Package @{ Id = 'A.B' } -DryRun | Should -Be 'planned'
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 0
    }

    It 'reports a failure' {
        Mock -ModuleName ShadowBox Test-WingetPackage { $false }
        Mock -ModuleName ShadowBox Invoke-Winget { 1 }
        Install-ShadowWingetPackage -Package @{ Id = 'A.B' } | Should -Be 'failed'
    }
}

Describe 'Update-ShadowWingetPackage' {
    It 'leaves self-updating apps alone' {
        Mock -ModuleName ShadowBox Invoke-Winget { 0 }
        Update-ShadowWingetPackage -Package @{ Id = 'Valve.Steam'; Upgrade = $false } | Should -Be 'skipped'
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 0
    }

    It 'treats "no applicable update" as current' {
        Mock -ModuleName ShadowBox Invoke-Winget { -1978335189 }
        Update-ShadowWingetPackage -Package @{ Id = 'A.B' } | Should -Be 'current'
    }
}

Describe 'Set-ShadowTweak' {
    It 'skips a disabled tweak without touching the registry' {
        Mock -ModuleName ShadowBox New-ItemProperty {}
        $t = @{ Name = 't'; Enabled = $false; Values = @(@{ Path = 'HKCU:\X'; Name = 'n'; Value = 1; Type = 'DWord' }) }
        Set-ShadowTweak -Tweak $t | Should -Be 'disabled'
        Should -Invoke -ModuleName ShadowBox New-ItemProperty -Times 0
    }

    It 'does not rewrite a value that is already set' {
        Mock -ModuleName ShadowBox Test-ShadowRegistryValue { $true }
        Mock -ModuleName ShadowBox New-ItemProperty {}
        $t = @{ Name = 't'; Enabled = $true; Values = @(@{ Path = 'HKCU:\X'; Name = 'n'; Value = 1; Type = 'DWord' }) }
        Set-ShadowTweak -Tweak $t | Should -Be 'present'
        Should -Invoke -ModuleName ShadowBox New-ItemProperty -Times 0
    }
}

Describe 'Invoke-ShadowSync' {
    It 'upgrades only on update, and only packages that allow it' {
        Mock -ModuleName ShadowBox Test-WingetPackage { $true }
        Mock -ModuleName ShadowBox Invoke-Winget { 0 }
        $config = @{
            Packages = @{ Winget = @(@{ Id = 'A.B' }, @{ Id = 'Valve.Steam'; Upgrade = $false }); Scoop = @{ Apps = @() } }
            Settings = @{ Tweaks = @() }
        }
        Invoke-ShadowSync -Config $config | Should -Be 0
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 0 -ParameterFilter { $Arguments[0] -eq 'upgrade' }

        Invoke-ShadowSync -Config $config -Upgrade | Should -Be 0
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'upgrade' -and $Arguments -contains 'A.B' }
        Should -Invoke -ModuleName ShadowBox Invoke-Winget -Times 0 -ParameterFilter { $Arguments -contains 'Valve.Steam' -and $Arguments[0] -eq 'upgrade' }
    }
}
