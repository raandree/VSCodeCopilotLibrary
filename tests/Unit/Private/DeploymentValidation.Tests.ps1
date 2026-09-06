BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
}

Describe 'Deployment path validation' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:contentPath = Join-Path $script:root 'content'
        $script:targetPath = Join-Path $script:root 'target'
        New-Item -ItemType Directory -Path (Join-Path $script:contentPath 'skills'), $script:targetPath -Force | Out-Null
    }

    It 'Should reject the mocked payload segment <Name> before planning writes' -ForEach @(
        @{ Name = 'bad:name.md' }
        @{ Name = 'trailing.' }
        @{ Name = 'trailing ' }
        @{ Name = 'CON.md' }
        @{ Name = 'bad|name.md' }
        @{ Name = '.' }
        @{ Name = '..' }
    ) {
        InModuleScope CopilotAtelier -Parameters @{
            ContentPath = $script:contentPath
            TargetPath = $script:targetPath
            PayloadSegment = $Name
        } {
            Mock Get-ChildItem {
                [pscustomobject]@{
                    FullName = (Join-Path $ContentPath 'skills') + [IO.Path]::DirectorySeparatorChar + $PayloadSegment
                    Attributes = [IO.FileAttributes]::Normal
                    PSIsContainer = $false
                }
            }
            Mock Get-FileHash { [pscustomobject]@{ Hash = ('A' * 64) } }

            { Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' } } |
                Should -Throw -ExpectedMessage '*Invalid Deployment record path*'

            Should -Invoke Get-FileHash -Times 0 -Exactly
        }
        @(Get-ChildItem -LiteralPath $script:targetPath -Force) | Should -HaveCount 0
    }

    It 'Should reject the record path <Path>' -ForEach @(
        @{ Path = 'skills/./file.md' }
        @{ Path = 'skills/../file.md' }
        @{ Path = 'skills//file.md' }
        @{ Path = 'skills/bad:name.md' }
        @{ Path = 'skills/trailing.' }
        @{ Path = 'skills/trailing ' }
        @{ Path = 'skills/CON.md' }
        @{ Path = 'skills/bad\name.md' }
    ) {
        @{ SchemaVersion = 1; Files = @(@{ Path = $Path; Sha256 = ('A' * 64) }) } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:targetPath '.copilotatelier.json')

        InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:targetPath } {
            { Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath } |
                Should -Throw -ExpectedMessage '*Invalid Deployment record path*'
        }
    }

    It 'Should round-trip every planned portable filename through the record reader' {
        foreach ($name in @('ordinary.md', 'two words.md', 'bracket[1].md', 'percent%name.md')) {
            Set-Content -LiteralPath (Join-Path $script:contentPath "skills/$name") -Value $name
        }

        InModuleScope CopilotAtelier -Parameters @{ ContentPath = $script:contentPath; TargetPath = $script:targetPath } {
            $plan = Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' }
            @{ SchemaVersion = 1; Files = @($plan.Files) } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $TargetPath '.copilotatelier.json')

            $record = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
            @($record.Files).Count | Should -Be 4
            $record.Files.Path | Should -Be $plan.Files.Path
            $record.Files.Sha256 | Should -Be $plan.Files.Sha256
        }
    }

    It 'Should reject an actual POSIX filename <Name> before writes' -Skip:$script:isWindowsPlatform -ForEach @(
        @{ Name = 'colon:name.md' }
        @{ Name = 'back\slash.md' }
        @{ Name = 'trailing.' }
        @{ Name = 'CON.md' }
    ) {
        [IO.File]::WriteAllText((Join-Path $script:contentPath "skills/$Name"), 'payload')

        InModuleScope CopilotAtelier -Parameters @{ ContentPath = $script:contentPath; TargetPath = $script:targetPath } {
            { Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' } } |
                Should -Throw -ExpectedMessage '*Invalid Deployment record path*'
        }
        @(Get-ChildItem -LiteralPath $script:targetPath -Force) | Should -HaveCount 0
    }
}

Describe 'Deployment filename identity' -Tag 'Unit' {
    BeforeAll {
        InModuleScope CopilotAtelier {
            if (-not (Get-Command Get-CopilotAtelierPathComparer -ErrorAction SilentlyContinue)) {
                function script:Get-CopilotAtelierPathComparer { [StringComparer]::OrdinalIgnoreCase }
            }
        }
    }

    BeforeEach {
        $script:identityRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:identityContent = Join-Path $script:identityRoot 'content'
        $script:identityTarget = Join-Path $script:identityRoot 'target'
        New-Item -ItemType Directory -Path (Join-Path $script:identityContent 'skills'), $script:identityTarget -Force | Out-Null
    }

    It 'Should apply mocked case-sensitive=<CaseSensitive> identity to planning and record round trips' -ForEach @(
        @{ CaseSensitive = $true }
        @{ CaseSensitive = $false }
    ) {
        InModuleScope CopilotAtelier -Parameters @{
            ContentPath = $script:identityContent
            TargetPath = $script:identityTarget
            UseCaseSensitive = $CaseSensitive
        } {
            Mock Get-CopilotAtelierPathComparer {
                if ($UseCaseSensitive) { [StringComparer]::Ordinal } else { [StringComparer]::OrdinalIgnoreCase }
            }
            Mock Get-ChildItem {
                foreach ($payloadName in @('Alpha.md', 'alpha.md')) {
                    [pscustomobject]@{
                        FullName = Join-Path $ContentPath "skills/$payloadName"
                        Attributes = [IO.FileAttributes]::Normal
                        PSIsContainer = $false
                    }
                }
            }
            Mock Get-FileHash { [pscustomobject]@{ Hash = ('A' * 64) } }
            if ($UseCaseSensitive) {
                $plan = Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' }
                @($plan.Files).Count | Should -Be 2
                @{ SchemaVersion = 1; Files = @($plan.Files) } | ConvertTo-Json -Depth 5 |
                    Set-Content -LiteralPath (Join-Path $TargetPath '.copilotatelier.json')
                $record = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
                @($record.Files | Where-Object Path -ceq 'skills/Alpha.md').Count | Should -Be 1
                @($record.Files | Where-Object Path -ceq 'skills/alpha.md').Count | Should -Be 1
            }
            else {
                { Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' } } |
                    Should -Throw -ExpectedMessage '*duplicate payload path*'
            }
        }
    }

    It 'Should read case-distinct record paths with a mocked case-sensitive filesystem' {
        @{ SchemaVersion = 1; Files = @(
            @{ Path = 'skills/Alpha.md'; Sha256 = ('A' * 64) }
            @{ Path = 'skills/alpha.md'; Sha256 = ('B' * 64) }
        ) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:identityTarget '.copilotatelier.json')

        InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:identityTarget } {
            Mock Get-CopilotAtelierPathComparer { [StringComparer]::Ordinal }
            @( (Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath).Files ).Count | Should -Be 2
        }
    }

    It 'Should reject exact duplicate record paths regardless of mocked case policy' -ForEach @(
        @{ CaseSensitive = $true }
        @{ CaseSensitive = $false }
    ) {
        @{ SchemaVersion = 1; Files = @(
            @{ Path = 'skills/alpha.md'; Sha256 = ('A' * 64) }
            @{ Path = 'skills/alpha.md'; Sha256 = ('B' * 64) }
        ) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:identityTarget '.copilotatelier.json')

        InModuleScope CopilotAtelier -Parameters @{ TargetPath = $script:identityTarget; UseCaseSensitive = $CaseSensitive } {
            Mock Get-CopilotAtelierPathComparer {
                if ($UseCaseSensitive) { [StringComparer]::Ordinal } else { [StringComparer]::OrdinalIgnoreCase }
            }
            { Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath } | Should -Throw -ExpectedMessage '*Invalid Deployment record path*'
        }
    }

    It 'Should retire the old spelling in a mocked case-sensitive case-only update' {
        @{ SchemaVersion = 1; Files = @(@{ Path = 'skills/alpha.md'; Sha256 = ('A' * 64) }) } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:identityTarget '.copilotatelier.json')

        InModuleScope CopilotAtelier -Parameters @{ ContentPath = $script:identityContent; TargetPath = $script:identityTarget } {
            $oldPath = Join-Path $TargetPath 'skills/alpha.md'
            Mock Get-CopilotAtelierPathComparer { [StringComparer]::Ordinal }
            Mock Get-ChildItem {
                [pscustomobject]@{ FullName = Join-Path $ContentPath 'skills/Alpha.md'; Attributes = [IO.FileAttributes]::Normal; PSIsContainer = $false }
            }
            Mock Test-Path -ParameterFilter { $LiteralPath -eq $oldPath } -MockWith { [string] $LiteralPath -ceq $oldPath }
            Mock Get-FileHash { [pscustomobject]@{ Hash = ('A' * 64) } }

            $plan = Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' }

            @($plan.Actions | Where-Object { $_.Action -eq 'Copy' -and $_.Path -ceq 'skills/Alpha.md' }).Count | Should -Be 1
            @($plan.Actions | Where-Object { $_.Action -eq 'Remove' -and $_.Path -ceq 'skills/alpha.md' }).Count | Should -Be 1
        }
    }

    It 'Should round-trip actual case-distinct files on a case-sensitive non-Windows filesystem' -Skip:$script:isWindowsPlatform {
        foreach ($name in @('Alpha.md', 'alpha.md')) {
            [IO.File]::WriteAllText((Join-Path $script:identityContent "skills/$name"), $name)
        }
        if (@(Get-ChildItem -LiteralPath (Join-Path $script:identityContent 'skills') -File).Count -ne 2) {
            Set-ItResult -Skipped -Because 'The test filesystem is case-insensitive.'
            return
        }
        InModuleScope CopilotAtelier -Parameters @{ ContentPath = $script:identityContent; TargetPath = $script:identityTarget } {
            $plan = Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $TargetPath -Directory @{ skills = 'skills' }
            @{ SchemaVersion = 1; Files = @($plan.Files) } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $TargetPath '.copilotatelier.json')
            @((Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath).Files).Count | Should -Be 2
        }
    }
}