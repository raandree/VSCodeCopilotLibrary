BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Uninstall-CopilotAtelier' -Tag 'Unit' {
    BeforeEach {
        $script:profile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -ProjectPath $script:projectPath
        $script:installation = Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment
        $script:recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
    }

    AfterEach {
        Restore-CopilotAtelierTestProfile -Original $script:profile.Original
    }

    It 'Should remove owned files and empty Discovery links but preserve user configuration' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $settingsHash = (Get-FileHash -LiteralPath $script:installation.SettingsPath).Hash

        $result = Uninstall-CopilotAtelier -Confirm:$false

        $result.RemovedFiles.Count | Should -BeGreaterThan 4
        Test-Path -LiteralPath $script:profile.TargetPath | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:profile.CopilotRoot 'skills') | Should -BeFalse
        (Get-FileHash -LiteralPath $script:installation.SettingsPath).Hash | Should -Be $settingsHash
        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Not -Throw
    }

    It 'Should preserve modified files and untracked files with their Discovery link' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $modifiedFile = Join-Path $script:profile.TargetPath 'skills/marker.md'
        $personalFile = Join-Path $script:profile.TargetPath 'skills/personal.md'
        Set-Content -LiteralPath $modifiedFile -Value 'modified workflow'
        Set-Content -LiteralPath $personalFile -Value 'personal workflow'

        $result = Uninstall-CopilotAtelier -Confirm:$false

        Get-Content -LiteralPath $modifiedFile -Raw | Should -Match 'modified workflow'
        Get-Content -LiteralPath $personalFile -Raw | Should -Match 'personal workflow'
        $result.PreservedFiles | Should -Contain 'skills/marker.md'
        Test-Path -LiteralPath (Join-Path $script:profile.CopilotRoot 'skills') | Should -BeTrue
        Test-Path -LiteralPath $script:recordPath | Should -BeTrue
    }

    It 'Should make no filesystem changes under WhatIf' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $before = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })

        Uninstall-CopilotAtelier -WhatIf | Out-Null

        $after = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })
        $after | Should -Be $before
    }

    It 'Should preserve a legacy deployment with no ownership hashes' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        '{"Version":"1.0.0","ContentPath":"old"}' | Set-Content -LiteralPath $script:recordPath

        $result = Uninstall-CopilotAtelier -Confirm:$false

        $result.RemovedFiles.Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'skills/marker.md') | Should -BeTrue
    }

    It 'Should reject unsafe record path <Path> before deleting anything' -ForEach @(
        @{ Path = '../outside.md' }
        @{ Path = 'skills/../../outside.md' }
        @{ Path = 'skills/marker.md:stream' }
        @{ Path = 'skills\marker.md' }
        @{ Path = 'skills//marker.md' }
        @{ Path = 'skills/marker.md.' }
        @{ Path = 'skills/NUL' }
        @{ Path = '/skills/marker.md' }
    ) {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $record = Get-Content -LiteralPath $script:recordPath -Raw | ConvertFrom-Json
        $record.Files[-1].Path = $Path
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:recordPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*Invalid Deployment record*'

        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
    }

    It 'Should refuse a reparse-point directory without following it' {
        Get-Command -Name Uninstall-CopilotAtelier -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        $skillPath = Join-Path $script:profile.TargetPath 'skills'
        $outside = Join-Path $TestDrive 'outside-uninstall'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'marker.md') -Value 'outside content'
        Remove-Item -LiteralPath $skillPath -Recurse -Force
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $skillPath -Target $outside | Out-Null
        try
        {
            { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*reparse point*'
            Get-Content -LiteralPath (Join-Path $outside 'marker.md') -Raw | Should -Match 'outside content'
            Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
        }
        finally
        {
            [IO.Directory]::Delete($skillPath, $false)
        }
    }

    It 'Should reject invalid ownership metadata <Case> before deleting files' -ForEach @(
        @{ Case = 'string schema'; Change = { param($Record) $Record.SchemaVersion = '1' } }
        @{ Case = 'Boolean schema'; Change = { param($Record) $Record.SchemaVersion = $true } }
        @{ Case = 'future schema'; Change = { param($Record) $Record.SchemaVersion = 2 } }
        @{ Case = 'duplicate path'; Change = { param($Record) $Record.Files[-1].Path = $Record.Files[0].Path } }
        @{ Case = 'invalid hash'; Change = { param($Record) $Record.Files[0].Sha256 = 'invalid' } }
    ) {
        $record = Get-Content -LiteralPath $script:recordPath -Raw | ConvertFrom-Json
        & $Change $record
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:recordPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*Invalid Deployment record*'
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
    }

    It 'Should reject a singleton array instead of treating its element as the record' {
        $recordText = Get-Content -LiteralPath $script:recordPath -Raw
        ('[' + $recordText + ']') | Set-Content -LiteralPath $script:recordPath

        { Uninstall-CopilotAtelier -Confirm:$false } | Should -Throw -ExpectedMessage '*Invalid Deployment record*'
        Test-Path -LiteralPath (Join-Path $script:profile.TargetPath 'agents/marker.md') | Should -BeTrue
    }

    It 'Should reject a filesystem root even during a preview' {
        { Uninstall-CopilotAtelier -TargetPath ([IO.Path]::GetPathRoot($TestDrive)) -WhatIf } |
            Should -Throw -ExpectedMessage '*filesystem root*'
    }
}
