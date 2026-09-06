function Uninstall-CopilotAtelier
{
    <#
        .SYNOPSIS
            Removes verified deployment files while preserving personal content.

        .DESCRIPTION
            Validates the entire Deployment record before removing files. Only
            regular files with a matching recorded SHA-256 are removed. Modified
            and untracked files are preserved, along with Discovery links needed
            to reach them. Empty managed directories and matching Discovery links
            are removed without following links. Legacy deployments without file
            ownership are reported and left untouched.

            VS Code settings, keybindings, environment variables, module versions,
            and native plugin installations are not removed. Their prior state
            is not owned by the Deployment record.

            A competing local operation on the same Canonical target is refused.
            Recover an interrupted apply with the updated Install-CopilotAtelier
            before removal. Coordination does not lock cloud sync across machines.

        .PARAMETER TargetPath
            Explicit Canonical target. Defaults to the normal profile resolver,
            which fails instead of prompting when OneDrive selection is ambiguous.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Uninstall-CopilotAtelier -WhatIf

            Previews removal without changing the profile.

        .EXAMPLE
            Uninstall-CopilotAtelier -TargetPath ~/CopilotAtelier -Confirm:$false

            Removes unchanged owned files from the selected deployment.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath
    )

    $ErrorActionPreference = 'Stop'
    $pathParameters = @{ NonInteractive = $true }
    if ($PSBoundParameters.ContainsKey('TargetPath'))
    {
        $pathParameters.TargetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath)
    }
    $path = Get-CopilotAtelierPath @pathParameters
    $record = Get-CopilotAtelierDeploymentRecord -TargetPath $path.TargetPath
    $removed = [System.Collections.Generic.List[string]]::new()
    $preserved = [System.Collections.Generic.List[string]]::new()
    $planned = [System.Collections.Generic.List[object]]::new()
    $directories = [System.Collections.Generic.HashSet[string]]::new((Get-CopilotAtelierPathComparer -Path $path.TargetPath))

    if ($null -eq $record -or $record.SchemaVersion -ne 1)
    {
        if ($null -ne $record)
        {
            Write-Warning -Message 'Legacy Deployment record has no file ownership. Nothing was removed.'
        }
        return [pscustomobject]@{ TargetPath = $path.TargetPath; RemovedFiles = @(); PreservedFiles = @(); PlannedFiles = @() }
    }
    if ($record.Applying)
    {
        throw 'An interrupted deployment must be recovered with Install-CopilotAtelier before removal.'
    }
    $recordHash = (Get-FileHash -LiteralPath $path.DeploymentManifestPath -Algorithm SHA256).Hash

    foreach ($file in $record.Files)
    {
        $destination = Join-Path -Path $path.TargetPath -ChildPath $file.Path
        $parent = Split-Path -Path $destination -Parent
        while ($parent -and $parent -ne $path.TargetPath)
        {
            $null = $directories.Add($parent)
            $parent = Split-Path -Path $parent -Parent
        }
        if (-not (Test-Path -LiteralPath $destination))
        {
            continue
        }
        if ((Test-Path -LiteralPath $destination -PathType Leaf) -and
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $file.Sha256)
        {
            $planned.Add($file)
        }
        else
        {
            $preserved.Add($file.Path)
            Write-Warning -Message "Preserved modified file '$($file.Path)'."
        }
    }

    if ($PSCmdlet.ShouldProcess($path.TargetPath, "Remove $($planned.Count) verified deployment files and empty managed directories"))
    {
        $deploymentLock = Enter-CopilotAtelierDeploymentLock -TargetPath $path.TargetPath
        try
        {
            if ((Get-FileHash -LiteralPath $path.DeploymentManifestPath -Algorithm SHA256).Hash -ne $recordHash)
            {
                throw 'Deployment changed before removal. Retry with the current Deployment record.'
            }
            foreach ($file in $planned)
            {
                $destination = Join-Path -Path $path.TargetPath -ChildPath $file.Path
                Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $path.TargetPath
                if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $file.Sha256)
                {
                    throw "Deployment changed during removal: '$($file.Path)'."
                }
                Remove-Item -LiteralPath $destination -Force -Confirm:$false
                $removed.Add($file.Path)
            }

            foreach ($directoryName in @('agents', 'instructions', 'skills', 'prompts', 'hooks'))
            {
                $null = $directories.Add((Join-Path -Path $path.TargetPath -ChildPath $directoryName))
            }
            foreach ($directory in $directories | Sort-Object -Property Length -Descending)
            {
                Assert-CopilotAtelierRegularPath -LiteralPath $directory -RootPath $path.TargetPath
                if ([System.IO.Directory]::Exists($directory) -and [System.IO.Directory]::GetFileSystemEntries($directory).Length -eq 0)
                {
                    [System.IO.Directory]::Delete($directory, $false)
                }
            }

            $linkRoots = @($path.CopilotRoot)
            foreach ($directoryName in @('agents', 'instructions', 'skills', 'prompts', 'hooks'))
            {
                $destination = Join-Path -Path $path.TargetPath -ChildPath $directoryName
                if (Test-Path -LiteralPath $destination)
                {
                    continue
                }
                $linkRoots = @($path.CopilotRoot)
                if ($directoryName -eq 'skills')
                {
                    $linkRoots += Join-Path -Path $path.UserHome -ChildPath '.claude'
                    $linkRoots += Join-Path -Path $path.UserHome -ChildPath '.agents'
                }
                foreach ($linkRoot in $linkRoots)
                {
                    Assert-CopilotAtelierRegularPath -LiteralPath $linkRoot -RootPath $linkRoot
                    $linkPath = Join-Path -Path $linkRoot -ChildPath $directoryName
                    $link = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
                    if ($null -eq $link -or -not $link.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) -or @($link.Target).Count -ne 1)
                    {
                        continue
                    }
                    $linkTarget = [string] @($link.Target)[0]
                    if (-not [System.IO.Path]::IsPathRooted($linkTarget))
                    {
                        $linkTarget = Join-Path -Path $linkRoot -ChildPath $linkTarget
                    }
                    $comparison = if ($path.IsWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
                    if ([string]::Equals([System.IO.Path]::GetFullPath($linkTarget).TrimEnd([char[]] '\/'), $destination.TrimEnd([char[]] '\/'), $comparison))
                    {
                        [System.IO.Directory]::Delete($linkPath, $false)
                    }
                }
            }

            if ($preserved.Count -eq 0)
            {
                Remove-Item -LiteralPath $path.DeploymentManifestPath -Force -Confirm:$false
            }
            if ([System.IO.Directory]::Exists($path.TargetPath) -and [System.IO.Directory]::GetFileSystemEntries($path.TargetPath).Length -eq 0)
            {
                [System.IO.Directory]::Delete($path.TargetPath, $false)
            }
        }
        finally
        {
            $deploymentLock.Dispose()
        }
    }

    [pscustomobject]@{
        TargetPath = $path.TargetPath
        RemovedFiles = @($removed)
        PreservedFiles = @($preserved)
        PlannedFiles = @($planned | ForEach-Object -Process { $_.Path })
    }
}
