BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module InvokeBuild -ErrorAction Stop
    $script:fixtureBuildInvoker = New-Module -ScriptBlock {
        Import-Module InvokeBuild -ErrorAction Stop
    }
    $script:fixtureBuildPath = Join-Path $PSScriptRoot 'Fixtures/TestResultSerialization.build.ps1'
    $script:serializationTypes = @('System.IO.FileInfo', 'System.Management.Automation.PSDriveInfo', 'System.Management.Automation.ProviderInfo')
    $script:originalSerializationTypeData = @(Get-TypeData -TypeName $script:serializationTypes | ForEach-Object { $_.Copy() })
    $parseErrors = $null
    $taskAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $script:repoRoot '.build/Initialize_TestResultSerialization.build.ps1'),
        [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors.Message -join [Environment]::NewLine) }
    $taskRegistration = $taskAst.Find({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'task'
    }, $true)
    $taskBody = $taskRegistration.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } | Select-Object -First 1
    $script:serializationAction = $taskBody.ScriptBlock.GetScriptBlock()
}

AfterAll {
    foreach ($typeName in $script:serializationTypes) {
        if (Get-TypeData -TypeName $typeName) { Remove-TypeData -TypeName $typeName -ErrorAction Stop }
    }
    foreach ($typeData in $script:originalSerializationTypeData)
    {
        Update-TypeData -TypeData $typeData -Force
    }
}

Describe 'Pester result serialization' -Tag 'Unit' {
    BeforeEach {
        foreach ($typeName in $script:serializationTypes) {
            if (Get-TypeData -TypeName $typeName) { Remove-TypeData -TypeName $typeName -ErrorAction Stop }
        }
        $callerTypeData = [System.Management.Automation.Runspaces.TypeData]::new('System.IO.FileInfo')
        $fileTypeData = $script:originalSerializationTypeData | Where-Object TypeName -eq 'System.IO.FileInfo'
        foreach ($member in $fileTypeData.Members.GetEnumerator()) {
            $callerTypeData.Members.Add($member.Key, $member.Value)
        }
        $callerTypeData.SerializationMethod = 'SpecificProperties'
        $callerTypeData.PropertySerializationSet = [System.Management.Automation.Runspaces.PropertySetData]::new([string[]]@('FullName'))
        Update-TypeData -TypeData $callerTypeData -Force
        Update-TypeData -TypeName System.IO.FileInfo -MemberType NoteProperty -MemberName SerializationFixture -Value 'preserved' -Force
        (Get-TypeData -TypeName System.IO.FileInfo).SerializationMethod | Should -Be 'SpecificProperties'
        $script:beforeSerialization = @{}
        foreach ($typeName in $script:serializationTypes) {
            $typeData = Get-TypeData -TypeName $typeName
            $script:beforeSerialization[$typeName] = [pscustomobject]@{
                Method = $typeData.SerializationMethod
                Source = $typeData.StringSerializationSource
                Members = @($typeData.Members.Keys | Sort-Object)
            }
        }
    }

    AfterEach {
        foreach ($typeName in $script:serializationTypes) {
            if (Get-TypeData -TypeName $typeName) { Remove-TypeData -TypeName $typeName -ErrorAction Stop }
        }
        foreach ($typeData in $script:originalSerializationTypeData) {
            Update-TypeData -TypeData $typeData -Force
        }
    }

    It 'preserves test evidence without serializing live filesystem-provider metadata' {
        $filePath = Join-Path $TestDrive 'fixture.txt'
        'test evidence' | Set-Content -LiteralPath $filePath
        $reportPath = Join-Path $TestDrive 'result.xml'
        $probe = [pscustomobject]@{ PreviousExit = $false; Initialized = $false; Failure = 'successful'; OutputPath = $TestDrive }
        $parameters = @{ File = $script:fixtureBuildPath; Initialize = $script:serializationAction; Probe = $probe; FixturePath = $filePath; ReportPath = $reportPath }
        & $script:fixtureBuildInvoker {
            param($BuildParameters)
            Invoke-Build @BuildParameters
        } $parameters

        $restored = Import-Clixml -LiteralPath $reportPath
        $restored.Result | Should -Be 'Passed'
        $restored.PassedCount | Should -Be 3
        $restored.FailedCount | Should -Be 0
        $restored.CodeCoverage.CoveragePercent | Should -Be 80
        $restored.CodeCoverage.CommandsExecutedCount | Should -Be 8
        [string] $restored.Item | Should -Be $filePath
        $restored.Item.PSDrive | Should -BeOfType ([string])
        $restored.Item.PSProvider | Should -BeOfType ([string])
        Get-Content -LiteralPath $reportPath -Raw | Should -Not -Match 'ImplementingType|PSSnapIn|System.Reflection'
        (Get-Item -LiteralPath $reportPath).Length | Should -BeLessThan 8192
    }

    It 'restores caller type data and prior cleanup after <Failure> completion' -ForEach @(
        @{ Failure = 'successful' }
        @{ Failure = 'task failure' }
        @{ Failure = 'export failure' }
    ) {
        $probe = [pscustomobject]@{ PreviousExit = $false; Initialized = $false; Failure = $Failure; OutputPath = $TestDrive }
        $parameters = @{
            File = $script:fixtureBuildPath
            Initialize = $script:serializationAction
            Probe = $probe
        }

        if ($Failure -eq 'successful') {
            & $script:fixtureBuildInvoker {
                param($BuildParameters)
                Invoke-Build @BuildParameters
            } $parameters
        }
        else {
            {
                & $script:fixtureBuildInvoker {
                    param($BuildParameters)
                    Invoke-Build @BuildParameters
                } $parameters
            } | Should -Throw
        }

        $probe.Initialized | Should -BeTrue
        foreach ($typeName in $script:serializationTypes) {
            $typeData = Get-TypeData -TypeName $typeName
            $typeData.SerializationMethod | Should -Be $script:beforeSerialization[$typeName].Method
            $typeData.StringSerializationSource | Should -Be $script:beforeSerialization[$typeName].Source
            @($typeData.Members.Keys | Sort-Object) | Should -Be $script:beforeSerialization[$typeName].Members
        }
        (Get-TypeData -TypeName System.IO.FileInfo).Members['SerializationFixture'].Value | Should -Be 'preserved'
        $probe.PreviousExit | Should -BeTrue
    }

    It 'configures serialization before the Sampler test task' {
        Import-Module powershell-yaml -ErrorAction Stop
        $configuration = Get-Content -LiteralPath (Join-Path $script:repoRoot 'build.yaml') -Raw | ConvertFrom-Yaml
        $configuration.BuildWorkflow.test[0] | Should -Be 'Initialize_TestResultSerialization'
    }

    It 'keeps expected fixture failures out of the parent build error count' {
        $probe = [pscustomobject]@{ PreviousExit = $false; Initialized = $false; Failure = 'task failure'; OutputPath = $TestDrive }
        $parameters = @{ File = $script:fixtureBuildPath; Initialize = $script:serializationAction; Probe = $probe }
        $buildResult = @{}

        Invoke-Build -File (Join-Path $PSScriptRoot 'Fixtures/TestResultSerializationParent.build.ps1') -Invoker $script:fixtureBuildInvoker -Parameters $parameters -Result $buildResult

        $probe.Initialized | Should -BeTrue
        $probe.PreviousExit | Should -BeTrue
        @($buildResult.Value.Errors).Count | Should -Be 0
    }
}
