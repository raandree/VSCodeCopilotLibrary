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
