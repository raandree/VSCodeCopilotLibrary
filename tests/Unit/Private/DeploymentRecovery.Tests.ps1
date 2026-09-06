BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Deployment recovery' -Tag 'Unit' {
    BeforeEach {
        $script:profile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -ProjectPath $script:projectPath
        Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment | Out-Null
    }

    AfterEach {
        Restore-CopilotAtelierTestProfile -Original $script:profile.Original
    }

    It 'Should not adopt matching untracked content created <Point> staging during an interrupted apply' -ForEach @(
        @{ Point = 'before' }
        @{ Point = 'after' }
    ) {
        Set-Content -LiteralPath (Join-Path $script:profile.ContentPath 'skills/concurrent.md') -Value 'incoming content'
        InModuleScope CopilotAtelier -Parameters @{
            ContentPath = $script:profile.ContentPath
            TargetPath = $script:profile.TargetPath
            FailurePoint = $Point
        } {
            $sourcePath = Join-Path $ContentPath 'skills/concurrent.md'
            $destinationPath = Join-Path $TargetPath 'skills/concurrent.md'
            $recordPath = Join-Path $TargetPath '.copilotatelier.json'
            $script:injectUntrackedCopy = $true
            Mock Assert-CopilotAtelierRegularPath -ParameterFilter {
                $script:injectUntrackedCopy -and $FailurePoint -eq 'before' -and
                [IO.Path]::GetFileName([string] $LiteralPath) -like '.copilotatelier-*.tmp' -and
                (Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json).PendingAction
            } -MockWith {
                $script:injectUntrackedCopy = $false
                [IO.File]::Copy($sourcePath, $destinationPath, $false)
                throw 'Injected untracked creation before staging.'
            }
            Mock Get-FileHash -ParameterFilter {
                $script:injectUntrackedCopy -and $FailurePoint -eq 'after' -and
                [IO.Path]::GetFileName([string] $LiteralPath) -like '.copilotatelier-*.tmp'
            } -MockWith {
                $script:injectUntrackedCopy = $false
                [IO.File]::Copy($sourcePath, $destinationPath, $false)
                $algorithm = [Security.Cryptography.SHA256]::Create()
                try {
                    [pscustomobject]@{ Hash = [BitConverter]::ToString($algorithm.ComputeHash([IO.File]::ReadAllBytes($LiteralPath))).Replace('-', '') }
                }
                finally { $algorithm.Dispose() }
            }
            $expectedFailure = if ($FailurePoint -eq 'before') { '*Injected untracked creation*' } else { '*changed during apply*' }

            { Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage $expectedFailure
            { Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*changed during interrupted apply*'

            (Get-FileHash -LiteralPath $destinationPath).Hash | Should -Be (Get-FileHash -LiteralPath $sourcePath).Hash
            (Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json).Files.Path | Should -Not -Contain 'skills/concurrent.md'
        }
    }

    It 'Should preserve matching untracked staging content during recovery' {
        $recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        $file = $record.Files | Where-Object Path -eq 'skills/marker.md'
        $stageRelativePath = 'skills/.copilotatelier-' + [guid]::NewGuid().ToString('N') + '.tmp'
        $stagePath = Join-Path $script:profile.TargetPath $stageRelativePath
        Copy-Item -LiteralPath (Join-Path $script:profile.TargetPath $file.Path) -Destination $stagePath
        $record | Add-Member -NotePropertyName Applying -NotePropertyValue $true
        $record | Add-Member -NotePropertyName PendingAction -NotePropertyValue ([pscustomobject]@{
                Action = 'Copy'
                Path = $file.Path
                Sha256 = $file.Sha256
                PreviousSha256 = $file.Sha256
                StagePath = $stageRelativePath
                StageReady = $true
            })
        $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recordPath

        Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment | Out-Null

        Test-Path -LiteralPath $stagePath | Should -BeTrue
        (Get-FileHash -LiteralPath $stagePath).Hash | Should -Be $file.Sha256
        (Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json).Files.Path | Should -Not -Contain $stageRelativePath
    }

    It 'Should recover a <Kind> file interrupted after copy with the <Retry> payload' -ForEach @(
        @{ Kind = 'recorded'; Retry = 'same' }
        @{ Kind = 'recorded'; Retry = 'different' }
        @{ Kind = 'recorded'; Retry = 'older' }
        @{ Kind = 'new'; Retry = 'same' }
        @{ Kind = 'new'; Retry = 'different' }
        @{ Kind = 'new'; Retry = 'older' }
    ) {
        $relativePath = if ($Kind -eq 'new') { 'skills/new.md' } else { 'skills/marker.md' }
        $sourcePath = Join-Path $script:profile.ContentPath $relativePath
        $originalText = if (Test-Path -LiteralPath $sourcePath) { Get-Content -LiteralPath $sourcePath -Raw } else { $null }
        Set-Content -LiteralPath $sourcePath -Value 'second payload'

        InModuleScope CopilotAtelier -Parameters @{
            ContentPath = $script:profile.ContentPath
            TargetPath = $script:profile.TargetPath
            RelativePath = $relativePath
            SourcePath = $sourcePath
            OriginalText = $originalText
            RetryPayload = $Retry
        } {
            $destinationPath = Join-Path $TargetPath $RelativePath
            $nextHash = (Get-FileHash -LiteralPath $SourcePath).Hash
            $script:interruptApply = $true
            Mock Get-FileHash -ParameterFilter { $LiteralPath -eq $destinationPath } -MockWith {
                $algorithm = [Security.Cryptography.SHA256]::Create()
                $stream = [IO.File]::OpenRead($LiteralPath)
                try {
                    $actual = [pscustomobject]@{ Hash = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '') }
                }
                finally {
                    $stream.Dispose()
                    $algorithm.Dispose()
                }
                if ($script:interruptApply -and $actual.Hash -eq $nextHash) {
                    $script:interruptApply = $false
                    throw 'Injected interruption after payload copy.'
                }
                $actual
            }

            { Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*Injected interruption*'

            $recordPath = Join-Path $TargetPath '.copilotatelier.json'
            { Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } | Should -Not -Throw
            $record = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
            ($record.Files | Where-Object Path -eq $RelativePath).Sha256 | Should -Be $nextHash
            $recordHash = (Get-FileHash -LiteralPath $recordPath).Hash
            Test-CopilotAtelier -TargetPath $TargetPath -Quiet | Should -BeFalse
            (Get-FileHash -LiteralPath $recordPath).Hash | Should -Be $recordHash

            if ($RetryPayload -eq 'different') {
                Set-Content -LiteralPath $SourcePath -Value 'third payload'
            }
            elseif ($RetryPayload -eq 'older') {
                if ($null -eq $OriginalText) {
                    Remove-Item -LiteralPath $SourcePath
                }
                else {
                    Set-Content -LiteralPath $SourcePath -Value $OriginalText -NoNewline
                }
            }

            { Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment } | Should -Not -Throw

            $record = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
            $record.PSObject.Properties.Name | Should -Not -Contain 'PendingAction'
            foreach ($file in $record.Files) {
                (Get-FileHash -LiteralPath (Join-Path $TargetPath $file.Path)).Hash | Should -Be $file.Sha256
            }
            if (Test-Path -LiteralPath $SourcePath) {
                (Get-FileHash -LiteralPath $destinationPath).Hash | Should -Be (Get-FileHash -LiteralPath $SourcePath).Hash
            }
            else {
                Test-Path -LiteralPath $destinationPath | Should -BeFalse
            }
        }
    }

    It 'Should recover removal interrupted before its record checkpoint' {
        $sourcePath = Join-Path $script:profile.ContentPath 'skills/marker.md'
        $originalText = Get-Content -LiteralPath $sourcePath -Raw
        Remove-Item -LiteralPath $sourcePath

        InModuleScope CopilotAtelier -Parameters @{
            ContentPath = $script:profile.ContentPath
            TargetPath = $script:profile.TargetPath
            OriginalText = $originalText
        } {
            $destinationPath = Join-Path $TargetPath 'skills/marker.md'
            Mock Remove-Item -ParameterFilter { $LiteralPath -eq $destinationPath } -MockWith {
                [IO.File]::Delete([string] $LiteralPath)
                throw 'Injected interruption after removal.'
            }
            { Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment } |
                Should -Throw -ExpectedMessage '*Injected interruption after removal*'

            (Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath).Files.Path |
                Should -Not -Contain 'skills/marker.md'
            Set-Content -LiteralPath (Join-Path $ContentPath 'skills/marker.md') -Value $OriginalText -NoNewline
            { Install-CopilotAtelier -ContentPath $ContentPath -SkipCopilotCliEnvironment } | Should -Not -Throw
            Get-Content -LiteralPath $destinationPath -Raw | Should -Be $OriginalText
        }
    }

    It 'Should preserve a readable record when Windows blocks atomic replacement' -Skip:(-not $script:isWindowsPlatform) {
        $recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
        $before = Get-Content -LiteralPath $recordPath -Raw
        $handle = [IO.File]::Open($recordPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            { Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment } | Should -Throw
            Get-Content -LiteralPath $recordPath -Raw | Should -Be $before
            { Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
        finally {
            $handle.Dispose()
        }
        { Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment } | Should -Not -Throw
    }

    It 'Should reject pending metadata with <Case>' -ForEach @(
        @{ Case = 'traversal'; Change = { param($Record) $Record.PendingAction.Path = 'skills/../outside.md' } }
        @{ Case = 'untracked overwrite'; Change = { param($Record) $Record.PendingAction.Path = 'skills/untracked.md' } }
        @{ Case = 'invalid hash'; Change = { param($Record) $Record.PendingAction.Sha256 = 'invalid' } }
        @{ Case = 'invalid action'; Change = { param($Record) $Record.PendingAction.Action = 'Execute' } }
        @{ Case = 'outside staging'; Change = { param($Record) $Record.PendingAction.StagePath = '../outside.tmp' } }
        @{ Case = 'owned staging'; Change = { param($Record) $Record.PendingAction.StagePath = 'skills/marker.md' } }
        @{ Case = 'non-Boolean state'; Change = { param($Record) $Record.Applying = 'true' } }
        @{ Case = 'non-Boolean staged state'; Change = { param($Record) $Record.PendingAction.StageReady = 'true' } }
    ) {
        $recordPath = Join-Path $script:profile.TargetPath '.copilotatelier.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        $record | Add-Member -NotePropertyName Applying -NotePropertyValue $true
        $record | Add-Member -NotePropertyName PendingAction -NotePropertyValue ([pscustomobject]@{
                Action = 'Copy'
                Path = 'skills/marker.md'
                Sha256 = ('A' * 64)
                PreviousSha256 = ($record.Files | Where-Object Path -eq 'skills/marker.md').Sha256
                StagePath = 'skills/.copilotatelier-' + [guid]::NewGuid().ToString('N') + '.tmp'
                StageReady = $false
            })
        & $Change $record
        $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recordPath
        $before = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash |
                ForEach-Object { "$($_.Path):$($_.Hash)" })

        { Install-CopilotAtelier -ContentPath $script:profile.ContentPath -SkipCopilotCliEnvironment } |
            Should -Throw -ExpectedMessage '*Invalid Deployment record*'

        @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force | Get-FileHash |
                ForEach-Object { "$($_.Path):$($_.Hash)" }) | Should -Be $before
    }

    It 'Should coordinate a real child-process <CommandName> attempt' -ForEach @(
        @{ CommandName = 'Install-CopilotAtelier' }
        @{ CommandName = 'Uninstall-CopilotAtelier' }
    ) {
        $handle = InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:profile.TargetPath } {
            Enter-CopilotAtelierDeploymentLock -TargetPath $TargetPath
        }
        $manifestPath = Join-Path (Get-Module CopilotAtelier).ModuleBase 'CopilotAtelier.psd1'
        $logPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.log')
        $resultPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.exit')
        $commandText = if ($CommandName -eq 'Install-CopilotAtelier') {
            "Install-CopilotAtelier -ContentPath '$($script:profile.ContentPath.Replace("'", "''"))' -SkipCopilotCliEnvironment -Confirm:`$false"
        }
        else {
            'Uninstall-CopilotAtelier -Confirm:$false'
        }
        $payload = {
            $ErrorActionPreference = 'Stop'
            & {
                Import-Module '__MANIFEST__' -Force
                try {
                    __COMMAND__
                    throw 'The competing operation was incorrectly allowed.'
                }
                catch {
                    if ($_.Exception.Message -notlike '*Deployment is in use*') { throw }
                    'Expected deployment coordination conflict.'
                }
            } *>&1 | Out-File -LiteralPath '__LOG__' -Encoding utf8
        }.ToString().Replace('__MANIFEST__', $manifestPath.Replace("'", "''")).Replace('__COMMAND__', $commandText + ' | Out-Null').Replace('__LOG__', $logPath.Replace("'", "''"))
        try {
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
            $launch = & (Join-Path $script:projectPath 'skills/long-running-job-monitor/scripts/Start-DetachedPowerShell.ps1') -EncodedCommand $encoded -ResultPath $resultPath
            $process = Get-Process -Id $launch.ProcessId -ErrorAction SilentlyContinue
            if ($process) { $process.WaitForExit(30000) | Should -BeTrue }
            Get-Content -LiteralPath $resultPath -Raw | Should -Be '0'
            Get-Content -LiteralPath $logPath -Raw | Should -Match 'Expected deployment coordination conflict'
        }
        finally {
            $handle.Dispose()
        }
        Test-CopilotAtelier -Quiet | Should -BeTrue
    }

    It 'Should refuse competing <CommandName> access without changing deployed files' -ForEach @(
        @{ CommandName = 'Install-CopilotAtelier' }
        @{ CommandName = 'Uninstall-CopilotAtelier' }
    ) {
        $targetName = (Split-Path -Path $script:profile.TargetPath -Leaf).ToUpperInvariant()
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            $key = [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($targetName))).Replace('-', '')
        }
        finally {
            $algorithm.Dispose()
        }
        $lockPath = Join-Path (Split-Path -Path $script:profile.TargetPath -Parent) ".copilotatelier-$key.lock"
        $handle = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $before = @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force |
                Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" })
        try {
            $parameters = @{ Confirm = $false }
            if ($CommandName -eq 'Install-CopilotAtelier') {
                $parameters.ContentPath = $script:profile.ContentPath
                $parameters.SkipCopilotCliEnvironment = $true
            }
            { & $CommandName @parameters } | Should -Throw -ExpectedMessage '*Deployment is in use*'
        }
        finally {
            $handle.Dispose()
        }

        @(Get-ChildItem -LiteralPath $script:profile.TargetPath -Recurse -File -Force |
                Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" }) | Should -Be $before
    }
}