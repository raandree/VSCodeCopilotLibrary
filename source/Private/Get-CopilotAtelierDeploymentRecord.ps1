function Get-CopilotAtelierDeploymentRecord
{
    [CmdletBinding(DefaultParameterSetName = 'File')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [System.Management.Automation.PSObject]
        $InputObject,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Raw
    )

    $recordPath = Join-Path -Path $TargetPath -ChildPath '.copilotatelier.json'
    Assert-CopilotAtelierRegularPath -LiteralPath $recordPath -RootPath $TargetPath
    if ($PSBoundParameters.ContainsKey('InputObject'))
    {
        $record = $InputObject
    }
    else
    {
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
    }
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

    $pathComparer = Get-CopilotAtelierPathComparer -Path $TargetPath
    $seenPath = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($file in $record.Files)
    {
        if ($file.Path -isnot [string] -or $file.Sha256 -isnot [string] -or $file.Sha256 -notmatch '\A[0-9a-fA-F]{64}\z')
        {
            throw 'Invalid Deployment record: each file requires a relative Path and SHA-256.'
        }

        Assert-CopilotAtelierDeploymentPath -Path $file.Path
        if (-not $seenPath.Add($file.Path))
        {
            throw "Invalid Deployment record path '$($file.Path)'."
        }

        Assert-CopilotAtelierRegularPath -LiteralPath (Join-Path -Path $TargetPath -ChildPath $file.Path) -RootPath $TargetPath
    }

    if ($record.PSObject.Properties.Name -contains 'Applying' -and $record.Applying -isnot [bool])
    {
        throw 'Invalid Deployment record: Applying must be a Boolean.'
    }
    if ($record.PSObject.Properties.Name -contains 'PendingAction')
    {
        $pending = $record.PendingAction
        if ($record.Applying -ne $true -or $pending -isnot [System.Management.Automation.PSCustomObject] -or
            @('Copy', 'Remove') -cnotcontains $pending.Action -or $pending.Path -isnot [string] -or
            $pending.Sha256 -isnot [string] -or $pending.Sha256 -notmatch '\A[0-9a-fA-F]{64}\z' -or
            ($null -ne $pending.PreviousSha256 -and ($pending.PreviousSha256 -isnot [string] -or $pending.PreviousSha256 -notmatch '\A[0-9a-fA-F]{64}\z')))
        {
            throw 'Invalid Deployment record: malformed PendingAction.'
        }
        Assert-CopilotAtelierDeploymentPath -Path $pending.Path
        $wasOwned = $seenPath.Contains($pending.Path)
        if (($null -ne $pending.PreviousSha256 -and -not $wasOwned) -or
            ($pending.Action -eq 'Remove' -and (-not $wasOwned -or $pending.PreviousSha256 -ne $pending.Sha256)))
        {
            throw 'Invalid Deployment record: PendingAction cannot overwrite untracked files.'
        }
        if ($pending.Action -eq 'Copy')
        {
            $parent = $pending.Path.Substring(0, $pending.Path.LastIndexOf('/') + 1)
            if ($pending.StageReady -isnot [bool] -or $pending.StagePath -isnot [string] -or
                $pending.StagePath -cnotmatch ('\A' + [regex]::Escape($parent) + '\.copilotatelier-[0-9a-f]{32}\.tmp\z') -or
                $seenPath.Contains($pending.StagePath))
            {
                throw 'Invalid Deployment record: invalid PendingAction StagePath.'
            }
            Assert-CopilotAtelierDeploymentPath -Path $pending.StagePath
            Assert-CopilotAtelierRegularPath -LiteralPath (Join-Path $TargetPath $pending.StagePath) -RootPath $TargetPath
        }
        elseif ($null -ne $pending.StagePath)
        {
            throw 'Invalid Deployment record: Remove cannot have a StagePath.'
        }
        $destination = Join-Path -Path $TargetPath -ChildPath $pending.Path
        Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $TargetPath
        if (-not $Raw)
        {
            $currentHash = if (Test-Path -LiteralPath $destination -PathType Leaf)
            {
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            }
            elseif (Test-Path -LiteralPath $destination)
            {
                throw "Deployment changed during interrupted apply: '$($pending.Path)' is not a file."
            }
            else { $null }
                if (($pending.Action -eq 'Copy' -and $pending.StageReady -and
                    -not (Test-Path -LiteralPath (Join-Path $TargetPath $pending.StagePath)) -and $currentHash -eq $pending.Sha256) -or
                ($pending.Action -eq 'Remove' -and $null -eq $currentHash))
            {
                $record.Files = @($record.Files | Where-Object { -not $pathComparer.Equals($_.Path, $pending.Path) })
                if ($pending.Action -eq 'Copy')
                {
                    $record.Files += [pscustomobject]@{ Path = $pending.Path; Sha256 = $pending.Sha256 }
                }
            }
            elseif ($currentHash -ne $pending.PreviousSha256)
            {
                throw "Deployment changed during interrupted apply: '$($pending.Path)'. Preserve and reconcile the conflicting content before retrying."
            }
        }
    }

    return $record
}
