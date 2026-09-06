param(
    [scriptblock] $Initialize,
    [psobject] $Probe,
    [string] $FixturePath,
    [string] $ReportPath
)

$fixtureState = @{
    Initialize = $Initialize
    Probe = $Probe
    FixturePath = $FixturePath
    ReportPath = $ReportPath
}

Exit-Build { $fixtureState.Probe.PreviousExit = $true }

task . {
    & $fixtureState.Initialize
    $fixtureState.Probe.Initialized = $true
    foreach ($typeName in @('System.IO.FileInfo', 'System.Management.Automation.PSDriveInfo', 'System.Management.Automation.ProviderInfo')) {
        if ((Get-TypeData -TypeName $typeName).SerializationMethod -ne 'String') {
            throw "Missing serialization guard: $typeName"
        }
    }
    if ($fixtureState.Probe.Failure -eq 'task failure') { throw 'Injected task failure.' }
    if ($fixtureState.Probe.Failure -eq 'export failure') {
        'cannot export to a directory' | Export-Clixml -LiteralPath $fixtureState.Probe.OutputPath
    }
    if ($fixtureState.FixturePath) {
        $item = Get-Item -LiteralPath $fixtureState.FixturePath
        if ($item.BaseName -ne 'fixture' -or $item.SerializationFixture -ne 'preserved') {
            throw 'Serialization overrides removed ordinary FileInfo members.'
        }
        [pscustomobject]@{
            Result = 'Passed'
            PassedCount = 3
            FailedCount = 0
            CodeCoverage = [pscustomobject]@{ CoveragePercent = 80; CommandsExecutedCount = 8 }
            Item = Get-Item -LiteralPath $fixtureState.FixturePath
        } | Export-Clixml -LiteralPath $fixtureState.ReportPath -Depth 5
    }
}