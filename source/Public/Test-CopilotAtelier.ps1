function Test-CopilotAtelier
{
    <#
        .SYNOPSIS
            Diagnoses a deployment without modifying files or running hooks.

        .DESCRIPTION
            Checks the Deployment record, file hashes, loaded version, Discovery
            links, required hook scripts, and VS Code settings. Reports legacy
            trees and duplicate skill Discovery links as warnings. The result
            contains structured Checks with Code, Severity, Path, and Message.
            IsHealthy means no Error was found; warnings still need review.

            This is a local consistency check, not proof of client-side Discovery
            or a security sandbox. It never downloads, repairs, executes hook
            scripts, changes the environment, or contacts the Gallery.

        .PARAMETER TargetPath
            Explicit Canonical target. Defaults to the normal profile resolver,
            which fails instead of prompting when OneDrive selection is ambiguous.

        .PARAMETER Quiet
            Returns only the IsHealthy Boolean for automation.

        .OUTPUTS
            System.Management.Automation.PSCustomObject
            System.Boolean

        .EXAMPLE
            (Test-CopilotAtelier).Checks | Format-Table Code, Severity, Message

            Displays the local deployment checks.

        .EXAMPLE
            Test-CopilotAtelier -TargetPath ~/CopilotAtelier -Quiet

            Checks one deployment and returns a Boolean.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject], [System.Boolean])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Quiet
    )

    $ErrorActionPreference = 'Stop'
    $pathParameters = @{ NonInteractive = $true }
    if ($PSBoundParameters.ContainsKey('TargetPath'))
    {
        $pathParameters.TargetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath)
    }
    $path = Get-CopilotAtelierPath @pathParameters
    $checks = [System.Collections.Generic.List[object]]::new()
    $record = $null
    try
    {
        $record = Get-CopilotAtelierDeploymentRecord -TargetPath $path.TargetPath
        if ($null -eq $record)
        {
            $checks.Add([pscustomobject]@{ Code = 'MissingDeploymentRecord'; Severity = 'Error'; Path = $path.DeploymentManifestPath; Message = 'No Deployment record exists. Install the Customizations first.' })
        }
        elseif ($record.SchemaVersion -ne 1)
        {
            $checks.Add([pscustomobject]@{ Code = 'LegacyDeploymentRecord'; Severity = 'Warning'; Path = $path.DeploymentManifestPath; Message = 'File ownership is unknown; automatic removal is disabled.' })
        }
        else
        {
            foreach ($file in $record.Files)
            {
                $filePath = Join-Path -Path $path.TargetPath -ChildPath $file.Path
                if (-not (Test-Path -LiteralPath $filePath -PathType Leaf))
                {
                    $checks.Add([pscustomobject]@{ Code = 'MissingFile'; Severity = 'Error'; Path = $filePath; Message = 'An owned file is missing or is no longer a regular file.' })
                }
                elseif ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ne $file.Sha256)
                {
                    $checks.Add([pscustomobject]@{ Code = 'ModifiedFile'; Severity = 'Warning'; Path = $filePath; Message = 'An owned file differs from the Deployment record. Reconcile it before updating.' })
                }
            }
            $checks.Add([pscustomobject]@{ Code = 'DeploymentRecord'; Severity = 'Information'; Path = $path.DeploymentManifestPath; Message = "Validated $(@($record.Files).Count) owned file entries." })
        }
    }
    catch
    {
        $record = $null
        $checks.Add([pscustomobject]@{ Code = 'InvalidDeploymentRecord'; Severity = 'Error'; Path = $path.DeploymentManifestPath; Message = $_.Exception.Message })
    }

    $moduleVersion = if ($ExecutionContext.SessionState.Module) { [string] $ExecutionContext.SessionState.Module.Version } else { $null }
    if ($record.Version -and $moduleVersion -and $record.Version -ne $moduleVersion)
    {
        $checks.Add([pscustomobject]@{ Code = 'VersionDrift'; Severity = 'Warning'; Path = $path.DeploymentManifestPath; Message = "Loaded version $moduleVersion differs from deployed version $($record.Version)." })
    }

    foreach ($directoryName in @('agents', 'instructions', 'skills', 'prompts', 'hooks'))
    {
        $linkPath = Join-Path -Path $path.CopilotRoot -ChildPath $directoryName
        $expectedTarget = Join-Path -Path $path.TargetPath -ChildPath $directoryName
        $link = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $link)
        {
            $checks.Add([pscustomobject]@{ Code = 'MissingDiscoveryLink'; Severity = 'Error'; Path = $linkPath; Message = 'The expected Discovery link is missing.' })
            continue
        }
        if (-not $link.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint))
        {
            $checks.Add([pscustomobject]@{ Code = 'UnmanagedDiscoveryPath'; Severity = 'Warning'; Path = $linkPath; Message = 'This is a real directory or file, not a managed Discovery link. It was left untouched.' })
            continue
        }
        $linkTarget = [string] @($link.Target)[0]
        if (-not [System.IO.Path]::IsPathRooted($linkTarget))
        {
            $linkTarget = Join-Path -Path $path.CopilotRoot -ChildPath $linkTarget
        }
        $comparison = if ($path.IsWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        if (-not [string]::Equals([System.IO.Path]::GetFullPath($linkTarget).TrimEnd([char[]] '\/'), $expectedTarget.TrimEnd([char[]] '\/'), $comparison))
        {
            $checks.Add([pscustomobject]@{ Code = 'WrongDiscoveryTarget'; Severity = 'Error'; Path = $linkPath; Message = "Discovery link does not point to '$expectedTarget'." })
        }
    }

    foreach ($scriptName in @('Block-RemoteMutation', 'Add-SessionContext', 'Write-SessionClose', 'Write-CompactionCheckpoint', 'Get-SessionElapsed'))
    {
        $scriptPath = Join-Path -Path $path.TargetPath -ChildPath "hooks/scripts/$scriptName.ps1"
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf))
        {
            $checks.Add([pscustomobject]@{ Code = 'MissingHookScript'; Severity = 'Error'; Path = $scriptPath; Message = "Required hook script '$scriptName.ps1' is missing." })
        }
    }

    $hookPath = Join-Path -Path $path.TargetPath -ChildPath 'hooks/hooks.json'
    try
    {
        Assert-CopilotAtelierRegularPath -LiteralPath $hookPath -RootPath $path.TargetPath
        $hookConfiguration = Get-Content -LiteralPath $hookPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($eventName in @('PreToolUse', 'SessionStart', 'Stop', 'PreCompact'))
        {
            if (-not $hookConfiguration.hooks.$eventName)
            {
                throw "Missing hook event '$eventName'."
            }
        }
    }
    catch
    {
        $checks.Add([pscustomobject]@{ Code = 'InvalidHookConfiguration'; Severity = 'Error'; Path = $hookPath; Message = $_.Exception.Message })
    }

    try
    {
        $settings = ConvertFrom-Jsonc -Text (Get-Content -LiteralPath $path.SettingsPath -Raw -Encoding UTF8)
        if ($null -eq $settings -or $settings -isnot [System.Management.Automation.PSCustomObject])
        {
            throw 'VS Code settings must contain a JSON object.'
        }
        foreach ($settingName in @('chat.promptFilesLocations', 'chat.hookFilesLocations'))
        {
            $expectedLocation = if ($settingName -eq 'chat.promptFilesLocations') { '~/.copilot/prompts' } else { '~/.copilot/hooks' }
            if ($settings.$settingName.$expectedLocation -ne $true)
            {
                $checks.Add([pscustomobject]@{ Code = 'MissingDiscoverySetting'; Severity = 'Warning'; Path = $path.SettingsPath; Message = "Enable '$expectedLocation' in '$settingName'." })
            }
        }
    }
    catch
    {
        $checks.Add([pscustomobject]@{ Code = 'InvalidSettings'; Severity = 'Error'; Path = $path.SettingsPath; Message = $_.Exception.Message })
    }

    if ($path.OneDriveRoot -and (Test-Path -LiteralPath $path.LegacyLocalPath))
    {
        $checks.Add([pscustomobject]@{ Code = 'LegacyTree'; Severity = 'Warning'; Path = $path.LegacyLocalPath; Message = 'A second legacy tree exists. Review it before any manual cleanup.' })
    }
    foreach ($otherRoot in @('.claude', '.agents'))
    {
        $otherPath = Join-Path -Path $path.UserHome -ChildPath "$otherRoot/skills"
        $otherLink = Get-Item -LiteralPath $otherPath -Force -ErrorAction SilentlyContinue
        if ($otherLink -and $otherLink.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) -and
            [string] @($otherLink.Target)[0] -eq (Join-Path -Path $path.TargetPath -ChildPath 'skills'))
        {
            $checks.Add([pscustomobject]@{ Code = 'DuplicateSkillDiscovery'; Severity = 'Warning'; Path = $otherPath; Message = 'This additional skill Discovery link can duplicate entries in VS Code.' })
        }
    }

    $isHealthy = @($checks | Where-Object -FilterScript { $_.Severity -eq 'Error' }).Count -eq 0
    if ($Quiet)
    {
        return $isHealthy
    }
    [pscustomobject]@{
        TargetPath = $path.TargetPath
        Version = $moduleVersion
        DeployedVersion = $record.Version
        IsHealthy = $isHealthy
        Checks = @($checks)
    }
}
