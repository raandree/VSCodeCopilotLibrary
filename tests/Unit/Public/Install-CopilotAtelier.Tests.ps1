BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')
    $script:moduleName = 'CopilotAtelier'

    # The subdirectory under output/ is a Sampler setting, so it is matched rather than hard-coded.
    $builtManifest = @(
        Get-ChildItem -Path (Join-Path -Path $script:projectPath -ChildPath "output/*/$script:moduleName/*/$script:moduleName.psd1") -ErrorAction SilentlyContinue |
            Sort-Object -Property { [System.Version] $_.Directory.Name } -Descending
    )

    if (-not $builtManifest)
    {
        throw "The built module '$script:moduleName' was not found. Run './build.ps1 -Tasks build' first."
    }

    Import-Module -Name $builtManifest[0].FullName -Force -ErrorAction Stop

    $script:sandboxVariableName = @(
        'APPDATA'
        'HOME'
        'OneDrive'
        'OneDriveCommercial'
        'OneDriveConsumer'
        'USERPROFILE'
        'XDG_CONFIG_HOME'
    )

    function Initialize-CustomizationContent
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $Path
        )

        foreach ($directoryName in @('com.github.copilot/agents', 'com.github.copilot/rules', 'skills', 'com.github.copilot/commands', 'com.github.copilot/hooks'))
        {
            $directoryPath = Join-Path -Path $Path -ChildPath $directoryName

            New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null

            Set-Content -LiteralPath (Join-Path -Path $directoryPath -ChildPath 'marker.md') -Value "# $directoryName"
        }

        $keybindingPath = Join-Path -Path $Path -ChildPath 'keybindings'

        New-Item -ItemType Directory -Path $keybindingPath -Force | Out-Null

        @'
// A repository keybinding.
[
    { "key": "ctrl+k x", "command": "workbench.action.test" }
]
'@ | Set-Content -LiteralPath (Join-Path -Path $keybindingPath -ChildPath 'keybindings.json')
    }

    function Enter-Sandbox
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.String]
            $HomePath,

            [Parameter(Mandatory = $true)]
            [System.String]
            $ConfigPath
        )

        $original = @{}

        foreach ($name in $script:sandboxVariableName)
        {
            $original[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
        }

        New-Item -ItemType Directory -Path $HomePath, $ConfigPath -Force | Out-Null

        [System.Environment]::SetEnvironmentVariable('APPDATA', $ConfigPath, 'Process')
        [System.Environment]::SetEnvironmentVariable('HOME', $HomePath, 'Process')
        [System.Environment]::SetEnvironmentVariable('OneDrive', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('OneDriveCommercial', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('OneDriveConsumer', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('USERPROFILE', $HomePath, 'Process')
        [System.Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $ConfigPath, 'Process')

        return $original
    }

    function Exit-Sandbox
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [System.Collections.Hashtable]
            $Original
        )

        foreach ($name in $script:sandboxVariableName)
        {
            [System.Environment]::SetEnvironmentVariable($name, $Original[$name], 'Process')
        }
    }
}

Describe 'Install-CopilotAtelier' -Tag 'Unit' {
    Context 'When deploying into a clean profile' {
        BeforeAll {
            $script:contentPath = Join-Path -Path $TestDrive -ChildPath 'content'
            $script:homePath = Join-Path -Path $TestDrive -ChildPath 'clean-home'
            $script:configPath = Join-Path -Path $TestDrive -ChildPath 'clean-config'

            Initialize-CustomizationContent -Path $script:contentPath

            $script:original = Enter-Sandbox -HomePath $script:homePath -ConfigPath $script:configPath

            try
            {
                $script:result = Install-CopilotAtelier -ContentPath $script:contentPath -SkipCopilotCliEnvironment
            }
            finally
            {
                Exit-Sandbox -Original $script:original
            }

            $script:targetPath = Join-Path -Path $script:homePath -ChildPath 'CopilotAtelier'
            $script:settingsPath = $script:result.SettingsPath
            $script:settingsDirectory = Split-Path -Path $script:settingsPath -Parent
            $script:settings = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        }

        It 'Should report the canonical target' {
            $script:result.TargetPath | Should -Be $script:targetPath
        }

        It 'Should copy <_> to the canonical target' -ForEach @('agents', 'instructions', 'skills', 'prompts', 'hooks') {
            $markerPath = Join-Path -Path (Join-Path -Path $script:targetPath -ChildPath $_) -ChildPath 'marker.md'

            Test-Path -LiteralPath $markerPath -PathType Leaf | Should -BeTrue
        }

        It 'Should record the deployed version' {
            $manifestPath = Join-Path -Path $script:targetPath -ChildPath '.copilotatelier.json'

            Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue

            $manifestText = Get-Content -LiteralPath $manifestPath -Raw
            $deployment = $manifestText | ConvertFrom-Json

            $deployment.Version | Should -Be (Get-Module -Name $script:moduleName).Version.ToString()
            $deployment.ContentPath | Should -Be $script:contentPath
            $manifestText | Should -Match '"InstalledOn":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        }

        It 'Should record each deployed file with a relative path and SHA-256' {
            $deployment = Get-Content -LiteralPath (Join-Path $script:targetPath '.copilotatelier.json') -Raw |
                ConvertFrom-Json

            $deployment.SchemaVersion | Should -Be 1
            @($deployment.Files).Count | Should -Be 5

            foreach ($file in $deployment.Files)
            {
                $file.Path | Should -Match '^(agents|instructions|skills|prompts|hooks)/marker\.md$'
                $file.Sha256 | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:targetPath $file.Path) -Algorithm SHA256).Hash
            }
        }

        It 'Should enable <Name>' -ForEach @(
            @{ Name = 'chat.includeApplyingInstructions'; Value = $true }
            @{ Name = 'chat.includeReferencedInstructions'; Value = $true }
            @{ Name = 'github.copilot.chat.agent.thinkingTool'; Value = $true }
            @{ Name = 'github.copilot.chat.search.semanticTextResults'; Value = $true }
            @{ Name = 'github.copilot.chat.skillTool.enabled'; Value = $true }
            @{ Name = 'github.copilot.chat.agent.maxRequests'; Value = 500 }
            @{ Name = 'gitlens.ai.vscode.model'; Value = 'copilot:claude-opus-5' }
        ) {
            $script:settings.$Name | Should -Be $Value
        }

        It 'Should register the prompt and hook discovery locations' {
            $script:settings.'chat.promptFilesLocations'.PSObject.Properties.Name |
                Should -Contain '~/.copilot/prompts'

            $script:settings.'chat.hookFilesLocations'.PSObject.Properties.Name |
                Should -Contain '~/.copilot/hooks'
        }

        It 'Should merge the repository keybindings' {
            $keybindingPath = Join-Path -Path $script:settingsDirectory -ChildPath 'keybindings.json'

            $keybinding = @(Get-Content -LiteralPath $keybindingPath -Raw | ConvertFrom-Json)

            $keybinding.command | Should -Contain 'workbench.action.test'
        }

        It 'Should link <_> under the Copilot discovery root' -ForEach @('agents', 'instructions', 'skills', 'prompts', 'hooks') {
            $linkPath = Join-Path -Path (Join-Path -Path $script:homePath -ChildPath '.copilot') -ChildPath $_

            Test-Path -LiteralPath $linkPath | Should -BeTrue

            $link = Get-Item -LiteralPath $linkPath -Force

            $link.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) | Should -BeTrue
        }
    }

    Context 'When legacy location settings are present' {
        BeforeAll {
            $script:contentPath = Join-Path -Path $TestDrive -ChildPath 'legacy-content'
            $script:homePath = Join-Path -Path $TestDrive -ChildPath 'legacy-home'
            $script:configPath = Join-Path -Path $TestDrive -ChildPath 'legacy-config'

            Initialize-CustomizationContent -Path $script:contentPath

            $script:original = Enter-Sandbox -HomePath $script:homePath -ConfigPath $script:configPath

            try
            {
                # The VS Code configuration root is platform-specific, so the resolver decides where to seed.
                $settingsDirectory = (
                    InModuleScope -ModuleName $script:moduleName { Get-CopilotAtelierPath }
                ).SettingsDirectory

                New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null

                [ordered] @{
                    'chat.agentFilesLocations'        = [ordered] @{
                        '~/OneDrive/CopilotAtelier/Agents' = $true
                        '~/CopilotAtelier/Agents'          = $true
                    }
                    'chat.instructionsFilesLocations' = [ordered] @{
                        '~/CopilotAtelier/Instructions' = $true
                        '~/Other/Instructions'          = $true
                    }
                    'github.copilot.advanced.model'   = 'claude-opus-4.8'
                } |
                    ConvertTo-Json -Depth 5 |
                    Set-Content -LiteralPath (Join-Path -Path $settingsDirectory -ChildPath 'settings.json')

                Install-CopilotAtelier -ContentPath $script:contentPath -SkipCopilotCliEnvironment | Out-Null
            }
            finally
            {
                Exit-Sandbox -Original $script:original
            }

            $script:settings = Get-Content -LiteralPath (Join-Path -Path $settingsDirectory -ChildPath 'settings.json') -Raw |
                ConvertFrom-Json
        }

        It 'Should remove a location map that only held repository entries' {
            $script:settings.PSObject.Properties.Name | Should -Not -Contain 'chat.agentFilesLocations'
        }

        It 'Should remove repository entries but keep unrelated ones' {
            $locationName = @($script:settings.'chat.instructionsFilesLocations'.PSObject.Properties.Name)

            $locationName | Should -Not -Contain '~/CopilotAtelier/Instructions'
            $locationName | Should -Contain '~/Other/Instructions'
        }

        It 'Should remove the inert completions model key' {
            $script:settings.PSObject.Properties.Name | Should -Not -Contain 'github.copilot.advanced.model'
        }
    }

    Context 'When the content path holds no customization directory' {
        It 'Should throw a directed error' {
            $emptyPath = Join-Path -Path $TestDrive -ChildPath 'empty-content'

            New-Item -ItemType Directory -Path $emptyPath -Force | Out-Null

            { Install-CopilotAtelier -ContentPath $emptyPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage "*No customization directory found*"
        }
    }

    Context 'When updating a deployed tree' {
        BeforeEach {
            $script:updateRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:updateContent = Join-Path $script:updateRoot 'content'
            Initialize-CustomizationContent -Path $script:updateContent
            $script:updateOriginal = Enter-Sandbox -HomePath (Join-Path $script:updateRoot 'home') -ConfigPath (Join-Path $script:updateRoot 'config')
            $script:updateResult = Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment
        }

        AfterEach {
            Exit-Sandbox -Original $script:updateOriginal
        }

        It 'Should select an explicit destination without prompting for either OneDrive account' {
            $consumer = Join-Path $script:updateRoot 'consumer'
            $commercial = Join-Path $script:updateRoot 'commercial'
            New-Item -ItemType Directory -Path $consumer, $commercial -Force | Out-Null
            $env:OneDriveConsumer = $consumer
            $env:OneDriveCommercial = $commercial
            Mock Read-Host -ModuleName CopilotAtelier { throw 'Unexpected account prompt.' }
            $selected = Join-Path $script:updateRoot 'selected'

            $result = Install-CopilotAtelier -ContentPath $script:updateContent -TargetPath $selected -SkipCopilotCliEnvironment

            $result.TargetPath | Should -Be $selected
            Test-Path -LiteralPath (Join-Path $selected '.copilotatelier.json') | Should -BeTrue
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should reject ambiguous install account selection without reaching Read-Host' {
            $consumer = Join-Path $script:updateRoot 'consumer'
            $commercial = Join-Path $script:updateRoot 'commercial'
            New-Item -ItemType Directory -Path $consumer, $commercial -Force | Out-Null
            $env:OneDriveConsumer = $consumer
            $env:OneDriveCommercial = $commercial
            Mock Read-Host -ModuleName CopilotAtelier { throw 'Unexpected account prompt.' }

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*Specify -TargetPath*'

            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should preview an explicit destination without creating it' {
            $selected = Join-Path $script:updateRoot 'preview-selected'
            Install-CopilotAtelier -ContentPath $script:updateContent -TargetPath $selected -SkipCopilotCliEnvironment -WhatIf | Out-Null
            Test-Path -LiteralPath $selected | Should -BeFalse
        }

        It 'Should preserve user-added files without claiming ownership' {
            $userFile = Join-Path $script:updateResult.TargetPath 'skills/personal.md'
            Set-Content -LiteralPath $userFile -Value 'personal workflow'

            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment | Out-Null

            Get-Content -LiteralPath $userFile -Raw | Should -Match 'personal workflow'
            $deployment = Get-Content -LiteralPath (Join-Path $script:updateResult.TargetPath '.copilotatelier.json') -Raw | ConvertFrom-Json
            $deployment.Files.Path | Should -Not -Contain 'skills/personal.md'
        }

        It 'Should refuse a changed deployed file before writing settings or other files' {
            $changedFile = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Set-Content -LiteralPath $changedFile -Value 'user change'
            $settingsHash = (Get-FileHash -LiteralPath $script:updateResult.SettingsPath).Hash
            $recordPath = Join-Path $script:updateResult.TargetPath '.copilotatelier.json'
            $recordHash = (Get-FileHash -LiteralPath $recordPath).Hash

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Force } |
                Should -Throw -ExpectedMessage '*conflict*'

            Get-Content -LiteralPath $changedFile -Raw | Should -Match 'user change'
            (Get-FileHash -LiteralPath $script:updateResult.SettingsPath).Hash | Should -Be $settingsHash
            (Get-FileHash -LiteralPath $recordPath).Hash | Should -Be $recordHash
        }

        It 'Should explicitly repair a modified Owned file without claiming personal files' {
            (Get-Command Install-CopilotAtelier).Parameters.Keys | Should -Contain 'Repair'
            $changedFile = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            $personalFile = Join-Path $script:updateResult.TargetPath 'skills/personal.md'
            Set-Content -LiteralPath $changedFile -Value 'modified content'
            Set-Content -LiteralPath $personalFile -Value 'personal content'

            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Repair | Out-Null

            (Get-FileHash -LiteralPath $changedFile).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $script:updateContent 'skills/marker.md')).Hash
            Get-Content -LiteralPath $personalFile -Raw | Should -Match 'personal content'
            $record = Get-Content -LiteralPath (Join-Path $script:updateResult.TargetPath '.copilotatelier.json') -Raw | ConvertFrom-Json
            $record.Files.Path | Should -Not -Contain 'skills/personal.md'
        }

        It 'Should preview repair without changing files or the Deployment record' {
            Set-Content -LiteralPath (Join-Path $script:updateResult.TargetPath 'skills/marker.md') -Value 'modified content'
            $before = @(Get-ChildItem -LiteralPath $script:updateRoot -Recurse -File -Force |
                Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })

            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Repair -WhatIf | Out-Null

            @(Get-ChildItem -LiteralPath $script:updateRoot -Recurse -File -Force |
                Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" }) | Should -Be $before
        }

        It 'Should refuse repair of an untracked file even with Force' {
            $recordPath = Join-Path $script:updateResult.TargetPath '.copilotatelier.json'
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $record.Files = @($record.Files | Where-Object Path -ne 'skills/marker.md')
            $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath
            $personalFile = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Set-Content -LiteralPath $personalFile -Value 'untracked content'

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Repair -Force } |
                Should -Throw -ExpectedMessage '*untracked*'

            Get-Content -LiteralPath $personalFile -Raw | Should -Match 'untracked content'
        }

        It 'Should not claim matching untracked content during repair' {
            $recordPath = Join-Path $script:updateResult.TargetPath '.copilotatelier.json'
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $record.Files = @($record.Files | Where-Object Path -ne 'skills/marker.md')
            $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath

            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Repair | Out-Null

            (Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json).Files.Path |
                Should -Not -Contain 'skills/marker.md'
        }

        It 'Should still detect changes made after repair planning' {
            $changedFile = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Set-Content -LiteralPath $changedFile -Value 'modified content'
            Mock -CommandName ConvertFrom-Jsonc -ModuleName CopilotAtelier -MockWith {
                Set-Content -LiteralPath (Join-Path $env:HOME 'CopilotAtelier/skills/marker.md') -Value 'concurrent edit'
                [pscustomobject]@{}
            }

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Repair } |
                Should -Throw -ExpectedMessage '*changed during*'

            Get-Content -LiteralPath $changedFile -Raw | Should -Match 'concurrent edit'
        }

        It 'Should not remove a modified retired file during repair' {
            $changedFile = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Set-Content -LiteralPath $changedFile -Value 'retain my edit'
            Remove-Item -LiteralPath (Join-Path $script:updateContent 'skills/marker.md')

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment -Repair } |
                Should -Throw -ExpectedMessage '*retired file*local changes*'

            Get-Content -LiteralPath $changedFile -Raw | Should -Match 'retain my edit'
        }

        It 'Should remove only unchanged files retired from the payload' {
            Remove-Item -LiteralPath (Join-Path $script:updateContent 'skills/marker.md')
            $userFile = Join-Path $script:updateResult.TargetPath 'skills/personal.md'
            Set-Content -LiteralPath $userFile -Value 'keep me'

            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment | Out-Null

            Test-Path -LiteralPath (Join-Path $script:updateResult.TargetPath 'skills/marker.md') | Should -BeFalse
            Test-Path -LiteralPath $userFile | Should -BeTrue
        }

        It 'Should update an unchanged owned file and refresh its hash' {
            Set-Content -LiteralPath (Join-Path $script:updateContent 'skills/marker.md') -Value 'new release'
            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment | Out-Null

            $destination = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Get-Content -LiteralPath $destination -Raw | Should -Match 'new release'
            $record = Get-Content -LiteralPath (Join-Path $script:updateResult.TargetPath '.copilotatelier.json') -Raw | ConvertFrom-Json
            ($record.Files | Where-Object Path -EQ 'skills/marker.md').Sha256 | Should -Be (Get-FileHash -LiteralPath $destination).Hash
        }

        It 'Should preserve an owned file changed after planning' {
            $changedPath = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Set-Content -LiteralPath (Join-Path $script:updateContent 'skills/marker.md') -Value 'new release'
            Mock -CommandName ConvertFrom-Jsonc -ModuleName CopilotAtelier -MockWith {
                $destination = Join-Path (Join-Path $env:HOME 'CopilotAtelier') 'skills/marker.md'
                Set-Content -LiteralPath $destination -Value 'concurrent user change'
                [pscustomobject]@{}
            }

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*changed during*'
            Get-Content -LiteralPath $changedPath -Raw | Should -Match 'concurrent user change'
        }

        It 'Should refuse a file blocking a destination directory before any writes' {
            $sourceDirectory = Join-Path $script:updateContent 'skills/blocked'
            New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $sourceDirectory 'child.md') -Value 'new payload'
            $blockingFile = Join-Path $script:updateResult.TargetPath 'skills/blocked'
            Set-Content -LiteralPath $blockingFile -Value 'personal content'
            $settingsDirectory = Split-Path -Parent $script:updateResult.SettingsPath
            $backupCount = @(Get-ChildItem -LiteralPath $settingsDirectory -Filter '*.bak').Count

            { Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*Deployment conflict*'

            Get-Content -LiteralPath $blockingFile -Raw | Should -Match 'personal content'
            @(Get-ChildItem -LiteralPath $settingsDirectory -Filter '*.bak').Count | Should -Be $backupCount
        }

        It 'Should support a trusted link above the selected payload root' {
            $aliasPath = Join-Path $TestDrive ('parent-alias-' + [guid]::NewGuid().ToString('N'))
            $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path $aliasPath -Target $script:updateRoot | Out-Null
            try
            {
                { Install-CopilotAtelier -ContentPath (Join-Path $aliasPath 'content') -SkipCopilotCliEnvironment } |
                    Should -Not -Throw
            }
            finally
            {
                [IO.Directory]::Delete($aliasPath, $false)
            }
        }

        It 'Should not claim an identical file absent from the Deployment record' {
            $recordPath = Join-Path $script:updateResult.TargetPath '.copilotatelier.json'
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $record.Files = @($record.Files | Where-Object Path -NE 'skills/marker.md')
            $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath

            Install-CopilotAtelier -ContentPath $script:updateContent -SkipCopilotCliEnvironment | Out-Null

            $updated = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $updated.Files.Path | Should -Not -Contain 'skills/marker.md'
            Uninstall-CopilotAtelier -Confirm:$false | Out-Null
            Test-Path -LiteralPath (Join-Path $script:updateResult.TargetPath 'skills/marker.md') | Should -BeTrue
        }

        It 'Should reject source content overlapping the Canonical target' {
            $recordPath = Join-Path $script:updateResult.TargetPath '.copilotatelier.json'
            $before = (Get-FileHash -LiteralPath $recordPath).Hash

            { Install-CopilotAtelier -ContentPath $script:updateResult.TargetPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*overlap*'

            (Get-FileHash -LiteralPath $recordPath).Hash | Should -Be $before
            Test-Path -LiteralPath (Join-Path $script:updateResult.TargetPath 'agents/marker.md') | Should -BeTrue
        }

        It 'Should resolve relative content from the current PowerShell location' {
            Set-Content -LiteralPath (Join-Path $script:updateContent 'skills/marker.md') -Value 'relative update'
            Push-Location -LiteralPath $script:updateRoot
            try
            {
                Install-CopilotAtelier -ContentPath './content' -SkipCopilotCliEnvironment | Out-Null
            }
            finally
            {
                Pop-Location
            }

            $destination = Join-Path $script:updateResult.TargetPath 'skills/marker.md'
            Test-Path -LiteralPath $destination -PathType Leaf | Should -BeTrue
            Get-Content -LiteralPath $destination -Raw | Should -Match 'relative update'
        }
    }

    Context 'When previewing with -WhatIf' {
        It 'Should not throw and should not create the canonical target' {
            $whatIfContentPath = Join-Path -Path $TestDrive -ChildPath 'whatif-content'
            $whatIfHomePath = Join-Path -Path $TestDrive -ChildPath 'whatif-home'
            $whatIfConfigPath = Join-Path -Path $TestDrive -ChildPath 'whatif-config'

            Initialize-CustomizationContent -Path $whatIfContentPath

            $original = Enter-Sandbox -HomePath $whatIfHomePath -ConfigPath $whatIfConfigPath

            try
            {
                { Install-CopilotAtelier -ContentPath $whatIfContentPath -SkipCopilotCliEnvironment -WhatIf } |
                    Should -Not -Throw
            }
            finally
            {
                Exit-Sandbox -Original $original
            }

            # A dry run must not touch the file system.
            $targetPath = Join-Path -Path $whatIfHomePath -ChildPath 'CopilotAtelier'

            Test-Path -LiteralPath $targetPath | Should -BeFalse
        }
    }
}
