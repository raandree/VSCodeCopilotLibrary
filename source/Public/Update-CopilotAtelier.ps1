function Update-CopilotAtelier
{
    <#
        .SYNOPSIS
            Updates the module from a PowerShell repository and redeploys the customizations.

        .DESCRIPTION
            Compares the installed module version with the newest version
            published to the repository, installs the newer version when there
            is one, and then deploys its customization content with
            Install-CopilotAtelier so the ~/.copilot discovery folders match the
            module that is now installed.

            The command requires the module to be installed from a repository.
            When the commands were dot-sourced from a repository clone, update
            the clone with git and run Install-CopilotAtelier instead.

        .PARAMETER Repository
            The PowerShell repository to check. Defaults to PSGallery.

        .PARAMETER TargetPath
            Explicit Canonical target passed to installation. Ambiguous OneDrive
            selection fails before querying the repository and never prompts.
            Not used with SkipDeployment.

        .PARAMETER Force
            Redeploys even when the installed version is already the newest one.

        .PARAMETER Repair
            Redeploys even without a newer version and passes Repair to
            Install-CopilotAtelier. Modified Owned files still in the payload
            are replaced without backup; untracked files are never overwritten.
            Cannot be combined with SkipDeployment. This command still queries
            the repository; use Install-CopilotAtelier -Repair for offline repair.

        .PARAMETER SkipDeployment
            Installs the newer module version but does not deploy it. Use it to
            stage an update and deploy later with Install-CopilotAtelier.

        .PARAMETER IncludeClaudeCodeLinks
            Passed through to Install-CopilotAtelier so the redeployment keeps
            the Claude Code and agentskills.io links.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Update-CopilotAtelier -InformationAction Continue

            Updates from the PowerShell Gallery and redeploys the customizations.

        .EXAMPLE
            Update-CopilotAtelier -Force

            Redeploys the current version even when no newer version exists.

        .EXAMPLE
            Update-CopilotAtelier -TargetPath ~/CopilotAtelier -Repair -WhatIf

            Previews an update and repair at an explicitly selected destination.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Repository = 'PSGallery',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Repair,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipDeployment,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludeClaudeCodeLinks
    )

    $ErrorActionPreference = 'Stop'

    if ($Repair -and $SkipDeployment)
    {
        throw '-Repair cannot be combined with -SkipDeployment.'
    }
    $module = $ExecutionContext.SessionState.Module

    if (-not $module)
    {
        throw 'Update-CopilotAtelier requires the module to be imported from an installed copy. Running from a repository clone? Update the clone with git and run Install-CopilotAtelier.'
    }

    $installedVersion = $module.Version

    $deploymentTarget = $null
    if (-not $SkipDeployment)
    {
        $pathParameters = @{ NonInteractive = $true }
        if ($PSBoundParameters.ContainsKey('TargetPath'))
        {
            $pathParameters.TargetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath)
        }
        $deploymentTarget = (Get-CopilotAtelierPath @pathParameters).TargetPath
    }

    try
    {
        $availableModule = Find-Module -Name $module.Name -Repository $Repository
    }
    catch
    {
        throw "Unable to query repository '$Repository' for '$($module.Name)': $($_.Exception.Message)"
    }

    $availableVersion = [System.Version] $availableModule.Version

    Write-Information -MessageData "Installed version: $installedVersion"
    Write-Information -MessageData "Available version: $availableVersion ($Repository)"

    $updated = $false

    if ($availableVersion -gt $installedVersion)
    {
        if ($PSCmdlet.ShouldProcess($module.Name, "Update to version $availableVersion from '$Repository'"))
        {
            try
            {
                Update-Module -Name $module.Name -RequiredVersion $availableVersion -Force
            }
            catch
            {
                throw "Unable to update '$($module.Name)' to $availableVersion. Install it with Install-Module so it can be updated in place. Reported error: $($_.Exception.Message)"
            }

            $updated = $true

            Write-Information -MessageData "Updated to version $availableVersion."
        }
    }
    else
    {
        Write-Information -MessageData 'Already at the newest published version.'
    }

    $deployment = $null

    if ($SkipDeployment)
    {
        Write-Information -MessageData 'Skipped deployment as requested. Run Install-CopilotAtelier to deploy.'
    }
    elseif ($updated -or $Force -or $Repair)
    {
        $targetVersion = $installedVersion

        if ($updated)
        {
            $targetVersion = $availableVersion
        }

        $updatedModule = Import-Module -Name $module.Name -RequiredVersion $targetVersion -Force -PassThru

        $installParameter = @{
            IncludeClaudeCodeLinks = $IncludeClaudeCodeLinks
            TargetPath = $deploymentTarget
            Repair = $Repair
            WhatIf = $WhatIfPreference
        }
        if ($PSBoundParameters.ContainsKey('Confirm'))
        {
            $installParameter.Confirm = $PSBoundParameters.Confirm
        }

        $deployment = & $updatedModule {
            param
            (
                [System.Collections.Hashtable]
                $InstallParameter
            )

            Install-CopilotAtelier @InstallParameter
        } $installParameter
    }
    else
    {
        Write-Information -MessageData 'Nothing to deploy. Use -Force to redeploy the current version.'
    }

    return [PSCustomObject] @{
        Name            = $module.Name
        PreviousVersion = $installedVersion
        Version         = $availableVersion
        Updated         = $updated
        Deployment      = $deployment
    }
}
