BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../..')
    $script:moduleName = 'CopilotAtelier'
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')

    # The subdirectory under output/ is a Sampler setting, so it is matched rather than hard-coded.
    $builtManifest = @(
        Get-ChildItem -Path (Join-Path -Path $script:projectPath -ChildPath "output/*/$script:moduleName/*/$script:moduleName.psd1") -ErrorAction SilentlyContinue |
            Sort-Object -Property { [System.Version] $_.Directory.Name } -Descending
    )

    if (-not $builtManifest)
    {
        throw "The built module '$script:moduleName' was not found. Run './build.ps1 -Tasks build' first."
    }

    $script:moduleUnderTest = Import-Module -Name $builtManifest[0].FullName -Force -PassThru -ErrorAction Stop
    $script:installedVersion = $script:moduleUnderTest.Version
    $script:availableVersion = [System.Version]::new($script:installedVersion.Major + 1, 0, 0)
}

Describe 'Update-CopilotAtelier' -Tag 'Unit' {
    BeforeAll {
        $script:selectionProfile = New-CopilotAtelierTestProfile -Root (Join-Path $TestDrive 'update-profile') -ProjectPath $script:projectPath
        Mock -CommandName Update-Module -ModuleName $script:moduleName

        Mock -CommandName Import-Module -ModuleName $script:moduleName -MockWith {
            Get-Module -Name 'CopilotAtelier'
        }

        Mock -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -MockWith {
            [PSCustomObject] @{
                TargetPath = 'TestDrive:/CopilotAtelier'
            }
        }
    }

    AfterAll {
        Restore-CopilotAtelierTestProfile -Original $script:selectionProfile.Original
    }

    Context 'When the installed version is the newest one' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            $script:result = Update-CopilotAtelier
        }

        It 'Should not update the module' {
            $script:result.Updated | Should -BeFalse

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
        }

        It 'Should not redeploy' {
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
        }
    }

    Context 'When a newer version is published' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                $current = (Get-Module -Name 'CopilotAtelier').Version

                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = '{0}.0.0' -f ($current.Major + 1)
                }
            }

            $script:result = Update-CopilotAtelier
        }

        It 'Should update the module' {
            $script:result.Updated | Should -BeTrue
            $script:result.PreviousVersion | Should -Be $script:installedVersion
            $script:result.Version | Should -Be $script:availableVersion

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 1 -Exactly -Scope Context
        }

        It 'Should redeploy the customizations' {
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 1 -Exactly -Scope Context

            $script:result.Deployment | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When deployment is skipped' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                $current = (Get-Module -Name 'CopilotAtelier').Version

                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = '{0}.0.0' -f ($current.Major + 1)
                }
            }

            $script:result = Update-CopilotAtelier -SkipDeployment
        }

        It 'Should update but not deploy' {
            $script:result.Updated | Should -BeTrue

            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
        }
    }

    Context 'When redeployment is forced without a newer version' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                [PSCustomObject] @{
                    Name    = 'CopilotAtelier'
                    Version = (Get-Module -Name 'CopilotAtelier').Version.ToString()
                }
            }

            $script:result = Update-CopilotAtelier -Force
        }

        It 'Should redeploy the current version' {
            $script:result.Updated | Should -BeFalse

            Should -Invoke -CommandName Update-Module -ModuleName $script:moduleName -Times 0 -Exactly -Scope Context
            Should -Invoke -CommandName Install-CopilotAtelier -ModuleName $script:moduleName -Times 1 -Exactly -Scope Context
        }
    }

    Context 'When choosing a deployment destination' {
        BeforeAll {
            Mock Find-Module -ModuleName CopilotAtelier {
                [pscustomobject]@{ Name = 'CopilotAtelier'; Version = (Get-Module CopilotAtelier).Version.ToString() }
            }
            Mock Read-Host -ModuleName CopilotAtelier { throw 'Unexpected account prompt.' }
        }

        BeforeEach {
            $env:OneDriveConsumer = Join-Path $script:selectionProfile.HomePath 'consumer'
            $env:OneDriveCommercial = Join-Path $script:selectionProfile.HomePath 'commercial'
            New-Item -ItemType Directory -Path $env:OneDriveConsumer, $env:OneDriveCommercial -Force | Out-Null
        }

        AfterEach {
            $env:OneDriveConsumer = $null
            $env:OneDriveCommercial = $null
        }

        It 'Should forward the normalized explicit destination to installation' {
            $selected = Join-Path $script:selectionProfile.HomePath 'selected'
            Update-CopilotAtelier -TargetPath ($selected + [IO.Path]::DirectorySeparatorChar) -Force | Out-Null
            Should -Invoke Install-CopilotAtelier -ModuleName CopilotAtelier -Times 1 -Exactly -ParameterFilter { $TargetPath -eq $selected }
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should reject ambiguous deployment selection before querying the repository' {
            { Update-CopilotAtelier -Force } | Should -Throw -ExpectedMessage '*Specify -TargetPath*'
            Should -Invoke Find-Module -ModuleName CopilotAtelier -Times 0 -Exactly
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should not require an account when deployment is skipped' {
            { Update-CopilotAtelier -SkipDeployment } | Should -Not -Throw
            Should -Invoke Install-CopilotAtelier -ModuleName CopilotAtelier -Times 0 -Exactly
            Should -Invoke Read-Host -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should forward explicit repair and redeploy the current version' {
            $selected = Join-Path $script:selectionProfile.HomePath 'selected'
            Update-CopilotAtelier -TargetPath $selected -Repair | Out-Null
            Should -Invoke Install-CopilotAtelier -ModuleName CopilotAtelier -Times 1 -Exactly -ParameterFilter { $TargetPath -eq $selected -and $Repair }
            Should -Invoke Update-Module -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should reject repair combined with skipped deployment' {
            { Update-CopilotAtelier -Repair -SkipDeployment } | Should -Throw -ExpectedMessage '*Repair*SkipDeployment*'
            Should -Invoke Find-Module -ModuleName CopilotAtelier -Times 0 -Exactly
        }

        It 'Should expose destination, repair, and preview through the Setup script' {
            $parameters = (Get-Command (Join-Path $script:projectPath 'Setup-CopilotSettings.ps1')).Parameters.Keys
            $parameters | Should -Contain 'TargetPath'
            $parameters | Should -Contain 'Repair'
            $parameters | Should -Contain 'WhatIf'
        }
    }

    Context 'When the repository cannot be queried' {
        BeforeAll {
            Mock -CommandName Find-Module -ModuleName $script:moduleName -MockWith {
                throw 'No match was found.'
            }
        }

        It 'Should throw a directed error' {
            { Update-CopilotAtelier } |
                Should -Throw -ExpectedMessage "*Unable to query repository 'PSGallery'*"
        }
    }
}
