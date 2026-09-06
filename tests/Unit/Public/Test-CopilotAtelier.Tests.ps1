BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Test-CopilotAtelier' -Tag 'Unit' {
    BeforeEach {
        $script:profile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -ProjectPath $script:projectPath
        $script:installation = Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment
    }

    AfterEach {
        Restore-CopilotAtelierTestProfile -Original $script:profile.Original
    }

    It 'Should warn about a separately retained capitalized tree under a mocked case-sensitive policy' {
        Mock Get-CopilotAtelierPathComparer -ModuleName CopilotAtelier { [StringComparer]::Ordinal }
        Mock Test-Path -ModuleName CopilotAtelier -ParameterFilter {
            [IO.Path]::GetFileName([string] $LiteralPath) -cin @('Agents', 'Instructions', 'Skills', 'Prompts', 'Hooks')
        } -MockWith { [IO.Path]::GetFileName([string] $LiteralPath) -ceq 'Skills' }
        $before = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash |
            ForEach-Object { "$($_.Path):$($_.Hash)" })

        $result = Test-CopilotAtelier

        $legacy = @($result.Checks | Where-Object Code -eq 'LegacyTree')
        $legacy.Count | Should -Be 1
        $legacy[0].Path | Should -BeExactly (Join-Path $script:profile.TargetPath 'Skills')
        $legacy[0].Severity | Should -Be 'Warning'
        $result.IsHealthy | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash |
            ForEach-Object { "$($_.Path):$($_.Hash)" }) | Should -Be $before
    }

    It 'Should not mistake a case-insensitive directory alias for a second legacy tree' {
        Mock Get-CopilotAtelierPathComparer -ModuleName CopilotAtelier { [StringComparer]::OrdinalIgnoreCase }
        (Test-CopilotAtelier).Checks.Code | Should -Not -Contain 'LegacyTree'
    }

    It 'Should preserve and diagnose an actual separate capitalized tree' -Skip:$script:isWindowsPlatform {
        $legacyPath = Join-Path $script:profile.TargetPath 'Skills'
        New-Item -ItemType Directory -Path $legacyPath -Force | Out-Null
        $personalFile = Join-Path $legacyPath 'personal.md'
        Set-Content -LiteralPath $personalFile -Value 'retained legacy content'
        $directoryNames = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Directory | ForEach-Object Name)
        if ($directoryNames -cnotcontains 'skills' -or $directoryNames -cnotcontains 'Skills') {
            Set-ItResult -Skipped -Because 'The test filesystem is case-insensitive.'
            return
        }

        $result = Test-CopilotAtelier

        @($result.Checks | Where-Object { $_.Code -eq 'LegacyTree' -and $_.Path -ceq $legacyPath }).Count | Should -Be 1
        Get-Content -LiteralPath $personalFile -Raw | Should -Match 'retained legacy content'
    }

    It 'Should reject a reparse-point target when inspecting filename policy' {
        $aliasPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $aliasPath -Target $script:profile.TargetPath | Out-Null
        try {
            InModuleScope CopilotAtelier -Parameters @{ SelectedPath = $aliasPath } {
                { Get-CopilotAtelierPathComparer -Path $SelectedPath } | Should -Throw -ExpectedMessage '*reparse point*'
            }
            Test-CopilotAtelier -TargetPath $aliasPath -Quiet | Should -BeFalse
        }
        finally {
            [IO.Directory]::Delete($aliasPath, $false)
        }
    }

    It 'Should report a healthy deployment without changing any files' {
        Get-Command -Name Test-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $before = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })

        $result = Test-CopilotAtelier

        $result.IsHealthy | Should -BeTrue
        $result.TargetPath | Should -Be $script:profile.TargetPath
        Test-CopilotAtelier -Quiet | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" }) | Should -Be $before
    }

    It 'Should report changed and missing owned files' {
        Get-Command -Name Test-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Set-Content -LiteralPath (Join-Path $script:profile.TargetPath 'skills/marker.md') -Value 'changed'
        Remove-Item -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md')

        $result = Test-CopilotAtelier

        $result.IsHealthy | Should -BeFalse
        $result.Checks.Code | Should -Contain 'ModifiedFile'
        $result.Checks.Code | Should -Contain 'MissingFile'
    }

    It 'Should fail health for a modified hook file <RelativePath>' -ForEach @(
        @{ RelativePath = 'hooks/scripts/Block-RemoteMutation.ps1' }
        @{ RelativePath = 'hooks/scripts/Add-SessionContext.ps1' }
        @{ RelativePath = 'hooks/scripts/Write-SessionClose.ps1' }
        @{ RelativePath = 'hooks/scripts/Write-CompactionCheckpoint.ps1' }
        @{ RelativePath = 'hooks/scripts/Get-SessionElapsed.ps1' }
        @{ RelativePath = 'hooks/hooks.json' }
    ) {
        Add-Content -LiteralPath (Join-Path $script:profile.TargetPath $RelativePath) -Value ' '

        $result = Test-CopilotAtelier

        $result.IsHealthy | Should -BeFalse
        Test-CopilotAtelier -Quiet | Should -BeFalse
        @($result.Checks | Where-Object { $_.Code -eq 'ModifiedHookFile' -and $_.Severity -eq 'Error' }) |
            Should -HaveCount 1
    }

    It 'Should keep non-hook file modifications as warnings' {
        Set-Content -LiteralPath (Join-Path $script:profile.TargetPath 'skills/marker.md') -Value 'personal edit'

        $result = Test-CopilotAtelier

        $result.IsHealthy | Should -BeTrue
        Test-CopilotAtelier -Quiet | Should -BeTrue
        @($result.Checks | Where-Object { $_.Code -eq 'ModifiedFile' -and $_.Severity -eq 'Warning' }) |
            Should -HaveCount 1
    }

    It 'Should fail health for a modified required hook script without a trustworthy recorded hash' -ForEach @(
        @{ RecordMode = 'untracked' }
        @{ RecordMode = 'matching modified hash' }
    ) {
        $relativePath = 'hooks/scripts/Block-RemoteMutation.ps1'
        $scriptPath = Join-Path $script:profile.TargetPath $relativePath
        Set-Content -LiteralPath $scriptPath -Value 'exit 0'
        $recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        if ($RecordMode -eq 'untracked') {
            $record.Files = @($record.Files | Where-Object Path -ne $relativePath)
        }
        else {
            ($record.Files | Where-Object Path -eq $relativePath).Sha256 = (Get-FileHash -LiteralPath $scriptPath).Hash
        }
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath

        $result = Test-CopilotAtelier

        $result.IsHealthy | Should -BeFalse
        Test-CopilotAtelier -Quiet | Should -BeFalse
        $result.Checks.Code | Should -Contain 'ModifiedHookFile'
    }

    It 'Should reject a redirected <CommandField> hook even when its recorded hash matches' -ForEach @(
        @{ CommandField = 'command' }
        @{ CommandField = 'windows' }
        @{ CommandField = 'linux' }
        @{ CommandField = 'osx' }
    ) {
        $hookPath = Join-Path $script:profile.TargetPath 'hooks/hooks.json'
        $configuration = Get-Content -LiteralPath $hookPath -Raw | ConvertFrom-Json
        $configuration.hooks.PreToolUse[0] | Add-Member -MemberType NoteProperty -Name $CommandField -Value 'pwsh -NoProfile -NonInteractive -Command "exit 0"' -Force
        $configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hookPath
        $recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        ($record.Files | Where-Object Path -eq 'hooks/hooks.json').Sha256 = (Get-FileHash -LiteralPath $hookPath).Hash
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath

        $result = Test-CopilotAtelier

        $result.Checks.Code | Should -Contain 'InvalidHookConfiguration'
        $result.IsHealthy | Should -BeFalse
        Test-CopilotAtelier -Quiet | Should -BeFalse
    }

    It 'Should detect a Discovery link pointing elsewhere without repairing it' {
        Get-Command -Name Test-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $linkPath = Join-Path $script:profile.CopilotRoot 'skills'
        [IO.Directory]::Delete($linkPath, $false)
        $elsewhere = Join-Path $TestDrive 'other-skills'
        New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $linkPath -Target $elsewhere | Out-Null

        $result = Test-CopilotAtelier

        $result.Checks.Code | Should -Contain 'WrongDiscoveryTarget'
        (Get-Item -LiteralPath $linkPath -Force).Target | Should -Contain $elsewhere
    }

    It 'Should report missing hook scripts, version drift, and invalid settings' {
        Get-Command -Name Test-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Remove-Item -LiteralPath (Join-Path $script:profile.TargetPath 'hooks/scripts/Block-RemoteMutation.ps1')
        $recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        $record.Version = '0.0.0'
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath
        'not json' | Set-Content -LiteralPath $script:installation.SettingsPath

        $result = Test-CopilotAtelier

        $result.Checks.Code | Should -Contain 'MissingHookScript'
        $result.Checks.Code | Should -Contain 'VersionDrift'
        $result.Checks.Code | Should -Contain 'InvalidSettings'
    }

    It 'Should reject a settings root that is <Text>' -ForEach @(
        @{ Text = 'null' }
        @{ Text = '[]' }
        @{ Text = 'true' }
        @{ Text = '42' }
    ) {
        $Text | Set-Content -LiteralPath $script:installation.SettingsPath
        $result = Test-CopilotAtelier
        $result.Checks.Code | Should -Contain 'InvalidSettings'
        $result.IsHealthy | Should -BeFalse
    }

    It 'Should normalize an explicit target and avoid ambiguous account prompts' {
        $consumer = Join-Path $TestDrive 'consumer'
        $commercial = Join-Path $TestDrive 'commercial'
        New-Item -ItemType Directory -Path $consumer, $commercial -Force | Out-Null
        $env:OneDriveConsumer = $consumer
        $env:OneDriveCommercial = $commercial

        { Test-CopilotAtelier } | Should -Throw -ExpectedMessage '*Specify -TargetPath*'
        $result = Test-CopilotAtelier -TargetPath ($script:profile.TargetPath + [IO.Path]::DirectorySeparatorChar)
        $result.TargetPath | Should -Be $script:profile.TargetPath
        $result.IsHealthy | Should -BeTrue
    }
}
