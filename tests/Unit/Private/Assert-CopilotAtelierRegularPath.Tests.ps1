BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:cloudTagCases = @(0..15 | ForEach-Object { @{ Tag = ('9000{0:X}01A' -f $_) } })
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
    InModuleScope CopilotAtelier {
        if (-not (Get-Command Get-CopilotAtelierReparseTag -ErrorAction SilentlyContinue)) {
            function script:Get-CopilotAtelierReparseTag {
                param([string] $LiteralPath)
                throw "No native tag reader exists for '$LiteralPath'."
            }
        }
    }
}

Describe 'Deployment reparse-point classification' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:outsidePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:reparsePath = Join-Path $script:root 'placeholder'
        New-Item -ItemType Directory -Path $script:root, $script:outsidePath -Force | Out-Null
        $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $script:reparsePath -Target $script:outsidePath | Out-Null
    }

    AfterEach {
        [IO.Directory]::Delete($script:reparsePath, $false)
    }

    It 'Should accept modeled Windows Cloud Files metadata with tag <Tag>' -Skip:(-not $script:isWindowsPlatform) -ForEach $script:cloudTagCases {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath; TagText = $Tag } {
            Mock Get-CopilotAtelierReparseTag { [Convert]::ToUInt32($TagText, 16) }

            { Assert-CopilotAtelierRegularPath -LiteralPath $ReparsePath -RootPath $RootPath } | Should -Not -Throw

            Should -Invoke Get-CopilotAtelierReparseTag -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $ReparsePath }
        }
    }

    It 'Should still reject modeled redirecting or unknown tag <Tag>' -ForEach @(
        @{ Tag = 'A0000003' }
        @{ Tag = 'A000000C' }
        @{ Tag = '8000001B' }
        @{ Tag = '9000001C' }
        @{ Tag = 'B000601A' }
        @{ Tag = '9001001A' }
        @{ Tag = '00000000' }
    ) {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath; TagText = $Tag } {
            Mock Get-CopilotAtelierReparseTag { [Convert]::ToUInt32($TagText, 16) }

            { Assert-CopilotAtelierRegularPath -LiteralPath $ReparsePath -RootPath $RootPath } |
                Should -Throw -ExpectedMessage '*Refusing reparse point*'
        }
    }

    It 'Should preserve rejection of actual directory links without mocking metadata' {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath } {
            { Assert-CopilotAtelierRegularPath -LiteralPath $ReparsePath -RootPath $RootPath } | Should -Throw
        }
    }

    It 'Should reject a real nested link beneath a modeled cloud-placeholder directory' -Skip:(-not $script:isWindowsPlatform) {
        $nestedTarget = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $nestedLink = Join-Path $script:outsidePath 'nested'
        New-Item -ItemType Directory -Path $nestedTarget -Force | Out-Null
        New-Item -ItemType Junction -Path $nestedLink -Target $nestedTarget | Out-Null
        try {
            InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath } {
                Mock Get-CopilotAtelierReparseTag -ParameterFilter { $LiteralPath -eq $ReparsePath } -MockWith {
                    [Convert]::ToUInt32('9000601A', 16)
                }
                { Assert-CopilotAtelierRegularPath -LiteralPath (Join-Path $ReparsePath 'nested') -RootPath $RootPath } |
                    Should -Throw -ExpectedMessage '*Refusing reparse point*'
            }
        }
        finally {
            [IO.Directory]::Delete($nestedLink, $false)
        }
    }

    It 'Should not allow a cloud-tag exception on non-Windows platforms' -Skip:$script:isWindowsPlatform {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath } {
            Mock Get-CopilotAtelierReparseTag { [Convert]::ToUInt32('9000601A', 16) }

            { Assert-CopilotAtelierRegularPath -LiteralPath $ReparsePath -RootPath $RootPath } |
                Should -Throw -ExpectedMessage '*Refusing reparse point*'
            Should -Invoke Get-CopilotAtelierReparseTag -Times 0 -Exactly
        }
    }

    It 'Should read the native junction tag instead of following its target' -Skip:(-not $script:isWindowsPlatform) {
        InModuleScope CopilotAtelier -Parameters @{ ReparsePath = $script:reparsePath } {
            Get-CopilotAtelierReparseTag -LiteralPath $ReparsePath | Should -Be ([Convert]::ToUInt32('A0000003', 16))
        }
    }

    It 'Should read a literal ordinary file without changing it' -Skip:(-not $script:isWindowsPlatform) {
        $filePath = Join-Path $script:root 'metadata[1].md'
        Set-Content -LiteralPath $filePath -Value 'original content'
        $before = Get-Item -LiteralPath $filePath
        InModuleScope CopilotAtelier -Parameters @{ FilePath = $filePath } {
            Get-CopilotAtelierReparseTag -LiteralPath $FilePath | Should -Be 0
        }
        $after = Get-Item -LiteralPath $filePath
        $after.Attributes | Should -Be $before.Attributes
        $after.LastWriteTimeUtc | Should -Be $before.LastWriteTimeUtc
        Get-Content -LiteralPath $filePath -Raw | Should -Match 'original content'
    }

    It 'Should not create a missing file while querying its native tag' -Skip:(-not $script:isWindowsPlatform) {
        $missingPath = Join-Path $script:root 'missing.md'
        InModuleScope CopilotAtelier -Parameters @{ MissingPath = $missingPath } {
            { Get-CopilotAtelierReparseTag -LiteralPath $MissingPath } | Should -Throw
        }
        Test-Path -LiteralPath $missingPath | Should -BeFalse
    }

    It 'Should fail closed when reparse metadata cannot be read' -Skip:(-not $script:isWindowsPlatform) {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath } {
            Mock Get-CopilotAtelierReparseTag { throw 'Metadata query was denied.' }

            { Assert-CopilotAtelierRegularPath -LiteralPath $ReparsePath -RootPath $RootPath } |
                Should -Throw -ExpectedMessage '*Metadata query was denied*'
        }
    }

    It 'Should fail closed when reparse metadata is absent' -Skip:(-not $script:isWindowsPlatform) {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; ReparsePath = $script:reparsePath } {
            Mock Get-CopilotAtelierReparseTag { $null }

            { Assert-CopilotAtelierRegularPath -LiteralPath $ReparsePath -RootPath $RootPath } |
                Should -Throw -ExpectedMessage '*Refusing reparse point*'
        }
    }

    It 'Should validate a modeled cloud payload entry through the shared guard' {
        $contentPath = Join-Path $script:root 'content'
        $sourceRoot = Join-Path $contentPath 'skills'
        $targetPath = Join-Path $script:root 'target'
        New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        $sourceFilePath = Join-Path $sourceRoot 'placeholder.md'
        Set-Content -LiteralPath $sourceFilePath -Value 'payload content'

        InModuleScope CopilotAtelier -Parameters @{ ContentPath = $contentPath; SourceRoot = $sourceRoot; SourceFilePath = $sourceFilePath; TargetPath = $targetPath } {
            Mock Get-ChildItem -ParameterFilter { $LiteralPath -eq $SourceRoot } -MockWith {
                [pscustomobject]@{ FullName = $SourceFilePath; Attributes = [IO.FileAttributes]::ReparsePoint; PSIsContainer = $false }
            }

            $plan = Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' }

            $plan.Files.Path | Should -Be 'skills/placeholder.md'
            $plan.Actions.Action | Should -Be 'Copy'
            Test-Path -LiteralPath $TargetPath | Should -BeFalse
        }
    }

    It 'Should preserve containment even when the modeled tag is a cloud placeholder' {
        InModuleScope CopilotAtelier -Parameters @{ RootPath = $script:root; OutsidePath = $script:outsidePath } {
            Mock Get-CopilotAtelierReparseTag { [Convert]::ToUInt32('9000601A', 16) }

            { Assert-CopilotAtelierRegularPath -LiteralPath $OutsidePath -RootPath $RootPath } |
                Should -Throw -ExpectedMessage '*outside selected root*'
            Should -Invoke Get-CopilotAtelierReparseTag -Times 0 -Exactly
        }
    }
}