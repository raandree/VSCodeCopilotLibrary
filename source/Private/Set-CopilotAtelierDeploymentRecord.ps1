function Set-CopilotAtelierDeploymentRecord
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Record
    )

    $null = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -InputObject $Record -Raw
    $recordPath = Join-Path -Path $TargetPath -ChildPath '.copilotatelier.json'
    if (-not $PSCmdlet.ShouldProcess($recordPath, 'Write recoverable Deployment record'))
    {
        return
    }
    $temporaryPath = Join-Path -Path $TargetPath -ChildPath ('.copilotatelier-record-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    $stream = $null
    $created = $false
    try
    {
        Assert-CopilotAtelierRegularPath -LiteralPath $temporaryPath -RootPath $TargetPath
        $stream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $created = $true
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($Record | ConvertTo-Json -Depth 10))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        Assert-CopilotAtelierRegularPath -LiteralPath $recordPath -RootPath $TargetPath
        if ([System.IO.File]::Exists($recordPath))
        {
            [System.IO.File]::Replace($temporaryPath, $recordPath, [System.Management.Automation.Language.NullString]::Value)
        }
        else
        {
            [System.IO.File]::Move($temporaryPath, $recordPath)
        }
    }
    finally
    {
        if ($stream) { $stream.Dispose() }
        if ($created -and [System.IO.File]::Exists($temporaryPath))
        {
            Assert-CopilotAtelierRegularPath -LiteralPath $temporaryPath -RootPath $TargetPath
            Remove-Item -LiteralPath $temporaryPath -Force -Confirm:$false
        }
    }
}