BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:serializationTypes = @('System.IO.FileInfo', 'System.Management.Automation.PSDriveInfo', 'System.Management.Automation.ProviderInfo')
    $script:originalSerializationTypeData = @(Get-TypeData -TypeName $script:serializationTypes)
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
    Remove-TypeData -TypeName $script:serializationTypes -ErrorAction SilentlyContinue
    foreach ($typeData in $script:originalSerializationTypeData)
    {
        Update-TypeData -TypeData $typeData -Force
    }
}

Describe 'Pester result serialization' -Tag 'Unit' {
    It 'preserves test evidence without serializing live filesystem-provider metadata' {
        & $script:serializationAction
        foreach ($typeName in $script:serializationTypes)
        {
            (Get-TypeData -TypeName $typeName).SerializationMethod | Should -Be 'String'
        }

        $filePath = Join-Path $TestDrive 'fixture.txt'
        'test evidence' | Set-Content -LiteralPath $filePath
        $reportPath = Join-Path $TestDrive 'result.xml'
        [pscustomobject]@{
            Result = 'Passed'
            PassedCount = 3
            FailedCount = 0
            CodeCoverage = [pscustomobject]@{ CoveragePercent = 80; CommandsExecutedCount = 8 }
            Item = Get-Item -LiteralPath $filePath
        } | Export-Clixml -LiteralPath $reportPath -Depth 5

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

    It 'configures serialization before the Sampler test task' {
        Import-Module powershell-yaml -ErrorAction Stop
        $configuration = Get-Content -LiteralPath (Join-Path $script:repoRoot 'build.yaml') -Raw | ConvertFrom-Yaml
        $configuration.BuildWorkflow.test[0] | Should -Be 'Initialize_TestResultSerialization'
    }
}
