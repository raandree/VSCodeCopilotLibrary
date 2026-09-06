function Invoke-CopilotAtelierDeploymentPlan
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String] $TargetPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String] $ContentPath,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject] $Plan,

        [Parameter()]
        [AllowNull()]
        [System.String] $Version
    )

    $pathComparer = Get-CopilotAtelierPathComparer -Path $TargetPath
    $record = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
    if ($null -eq $record -or $record.SchemaVersion -ne 1)
    {
        $record = [pscustomobject]@{ SchemaVersion = 1; Version = $record.Version; Files = @() }
    }
    if ($record.PendingAction)
    {
        if ($record.PendingAction.StagePath)
        {
            $stagePath = Join-Path -Path $TargetPath -ChildPath $record.PendingAction.StagePath
            if (Test-Path -LiteralPath $stagePath)
            {
                Write-Warning -Message "Preserved abandoned staging file '$stagePath' for manual inspection. Matching bytes alone do not make it an Owned file."
            }
        }
        $record.PSObject.Properties.Remove('PendingAction')
    }
    $record | Add-Member -NotePropertyName Applying -NotePropertyValue $true -Force
    Set-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Record $record -Confirm:$false

    foreach ($action in $Plan.Actions)
    {
        $destination = Join-Path -Path $TargetPath -ChildPath $action.Path
        Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $TargetPath
        $currentHash = if (Test-Path -LiteralPath $destination) { (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash } else { $null }
        if ($currentHash -ne $action.PreviousSha256)
        {
            throw "Deployment changed during apply: '$($action.Path)'."
        }
        $stageRelativePath = $null
        if ($action.Action -eq 'Copy')
        {
            Assert-CopilotAtelierRegularPath -LiteralPath $action.SourcePath -RootPath $ContentPath
            if ((Get-FileHash -LiteralPath $action.SourcePath -Algorithm SHA256).Hash -ne $action.Sha256)
            {
                throw "Payload changed during deployment: '$($action.Path)'."
            }
            New-Item -ItemType Directory -Path (Split-Path -Path $destination -Parent) -Force | Out-Null
            $stageRelativePath = $action.Path.Substring(0, $action.Path.LastIndexOf('/') + 1) + '.copilotatelier-' + [guid]::NewGuid().ToString('N') + '.tmp'
        }
        $pending = [pscustomobject]@{
            Action = $action.Action
            Path = $action.Path
            Sha256 = $action.Sha256
            PreviousSha256 = $action.PreviousSha256
            StagePath = $stageRelativePath
            StageReady = $false
        }
        $record | Add-Member -NotePropertyName PendingAction -NotePropertyValue $pending -Force
        Set-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Record $record -Confirm:$false

        if ($action.Action -eq 'Copy')
        {
            $stagePath = Join-Path -Path $TargetPath -ChildPath $stageRelativePath
            Assert-CopilotAtelierRegularPath -LiteralPath $stagePath -RootPath $TargetPath
            $stageStream = $null
            $sourceStream = $null
            try
            {
                $stageStream = [System.IO.File]::Open($stagePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $sourceStream = [System.IO.File]::OpenRead($action.SourcePath)
                $sourceStream.CopyTo($stageStream)
                $stageStream.Flush($true)
            }
            finally
            {
                if ($sourceStream) { $sourceStream.Dispose() }
                if ($stageStream) { $stageStream.Dispose() }
            }
            if ((Get-FileHash -LiteralPath $stagePath -Algorithm SHA256).Hash -ne $action.Sha256)
            {
                throw "Payload changed during deployment: '$($action.Path)'."
            }
            $pending.StageReady = $true
            Set-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Record $record -Confirm:$false
        }

        Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $TargetPath
        $currentHash = if (Test-Path -LiteralPath $destination) { (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash } else { $null }
        if ($currentHash -ne $action.PreviousSha256)
        {
            throw "Deployment changed during apply: '$($action.Path)'."
        }
        if ($action.Action -eq 'Remove')
        {
            Remove-Item -LiteralPath $destination -Force -Confirm:$false
        }
        else
        {
            if ($null -eq $action.PreviousSha256)
            {
                [System.IO.File]::Move($stagePath, $destination)
            }
            else
            {
                [System.IO.File]::Replace($stagePath, $destination, [System.Management.Automation.Language.NullString]::Value)
            }
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $action.Sha256)
            {
                throw "Deployment verification failed for '$($action.Path)'."
            }
        }
        $record.Files = @($record.Files | Where-Object { -not $pathComparer.Equals($_.Path, $action.Path) })
        if ($action.Action -eq 'Copy')
        {
            $record.Files += [pscustomobject]@{ Path = $action.Path; Sha256 = $action.Sha256 }
        }
        $record.PSObject.Properties.Remove('PendingAction')
        Set-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Record $record -Confirm:$false
    }

    foreach ($file in $Plan.Files)
    {
        $destination = Join-Path -Path $TargetPath -ChildPath $file.Path
        Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $TargetPath
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $file.Sha256)
        {
            throw "Deployment changed during apply: '$($file.Path)'."
        }
    }
    $record.Files = @($Plan.Files)
    $record.Version = $Version
    $record | Add-Member -NotePropertyName InstalledOn -NotePropertyValue ([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')) -Force
    $record | Add-Member -NotePropertyName ContentPath -NotePropertyValue $ContentPath -Force
    $record.PSObject.Properties.Remove('Applying')
    Set-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Record $record -Confirm:$false
    return $record
}