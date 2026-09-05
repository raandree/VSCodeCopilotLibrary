function Get-CopilotAtelierDeploymentRecord
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath
    )

    $recordPath = Join-Path -Path $TargetPath -ChildPath '.copilotatelier.json'
    Assert-CopilotAtelierRegularPath -LiteralPath $recordPath -RootPath $TargetPath
    if (-not (Test-Path -LiteralPath $recordPath))
    {
        return
    }

    $recordText = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($recordText) -or -not $recordText.TrimStart().StartsWith('{'))
    {
        throw 'Invalid Deployment record: expected an object.'
    }
    $record = ConvertFrom-Json -InputObject $recordText -ErrorAction Stop
    if ($null -eq $record -or $record -isnot [System.Management.Automation.PSCustomObject])
    {
        throw 'Invalid Deployment record: expected an object.'
    }

    if ($record.PSObject.Properties.Name -notcontains 'SchemaVersion')
    {
        if ($record.PSObject.Properties.Name -contains 'Files')
        {
            throw 'Invalid Deployment record: Files requires SchemaVersion.'
        }
        return $record
    }

    if (($record.SchemaVersion -isnot [int] -and $record.SchemaVersion -isnot [long]) -or
        $record.SchemaVersion -ne 1 -or $record.Files -isnot [System.Array])
    {
        throw 'Invalid Deployment record: expected SchemaVersion 1 and a Files array.'
    }

    $seenPath = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $record.Files)
    {
        if ($file.Path -isnot [string] -or $file.Sha256 -isnot [string] -or $file.Sha256 -notmatch '\A[0-9a-fA-F]{64}\z')
        {
            throw 'Invalid Deployment record: each file requires a relative Path and SHA-256.'
        }

        $segments = $file.Path.Split('/')
        if ($segments.Count -lt 2 -or @('agents', 'instructions', 'skills', 'prompts', 'hooks') -cnotcontains $segments[0] -or
            $file.Path -match '[\\:\x00-\x1f<>"|?*]' -or -not $seenPath.Add($file.Path))
        {
            throw "Invalid Deployment record path '$($file.Path)'."
        }

        foreach ($segment in $segments)
        {
            if (-not $segment -or $segment -match '[. ]$' -or $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$')
            {
                throw "Invalid Deployment record path '$($file.Path)'."
            }
        }

        Assert-CopilotAtelierRegularPath -LiteralPath (Join-Path -Path $TargetPath -ChildPath $file.Path) -RootPath $TargetPath
    }

    return $record
}
