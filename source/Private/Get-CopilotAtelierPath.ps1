function Get-CopilotAtelierPath
{
    <#
        .SYNOPSIS
            Resolves every filesystem path the installer works with.

        .DESCRIPTION
            Determines the user profile, the VS Code user configuration
            directory, and the canonical customization target for the current
            platform. OneDrive is preferred for the target so a single synced
            copy serves every machine; the user profile is the fallback. When
            both a consumer and a commercial OneDrive are present the caller is
            asked which one to use.

        .PARAMETER TargetName
            The folder name used for the canonical target. Defaults to
            CopilotAtelier, which is also the module name.

        .PARAMETER TargetPath
            An explicitly selected Canonical target, bypassing account selection.

        .PARAMETER NonInteractive
            Fails with a directed error instead of prompting for an account.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierPath

            Returns the resolved profile, settings, and canonical target paths.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetName = 'CopilotAtelier',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $NonInteractive
    )

    $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    $isMacOSPlatform = $false
    $isMacOSVariable = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue

    if ($isMacOSVariable)
    {
        $isMacOSPlatform = [System.Boolean] $isMacOSVariable.Value
    }

    if ($isWindowsPlatform -and -not [System.String]::IsNullOrWhiteSpace($env:USERPROFILE))
    {
        $userHome = $env:USERPROFILE
    }
    elseif (-not [System.String]::IsNullOrWhiteSpace($env:HOME))
    {
        $userHome = $env:HOME
    }
    else
    {
        $userHome = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    }

    if ([System.String]::IsNullOrWhiteSpace($userHome))
    {
        throw 'Unable to resolve the current user profile directory.'
    }

    if ($isWindowsPlatform)
    {
        $configRoot = $env:APPDATA

        if ([System.String]::IsNullOrWhiteSpace($configRoot))
        {
            $configRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
        }
    }
    elseif ($isMacOSPlatform)
    {
        $configRoot = Join-Path -Path $userHome -ChildPath 'Library/Application Support'
    }
    elseif (-not [System.String]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME))
    {
        $configRoot = $env:XDG_CONFIG_HOME
    }
    else
    {
        $configRoot = Join-Path -Path $userHome -ChildPath '.config'
    }

    if ([System.String]::IsNullOrWhiteSpace($configRoot))
    {
        throw 'Unable to resolve the VS Code configuration directory.'
    }

    $oneDriveCandidate = [ordered] @{}

    if ($env:OneDriveConsumer -and (Test-Path -LiteralPath $env:OneDriveConsumer))
    {
        $oneDriveCandidate['Consumer'] = $env:OneDriveConsumer
    }

    if ($env:OneDriveCommercial -and (Test-Path -LiteralPath $env:OneDriveCommercial))
    {
        $oneDriveCandidate['Commercial'] = $env:OneDriveCommercial
    }

    $oneDriveRoot = $null

    if ($PSBoundParameters.ContainsKey('TargetPath'))
    {
        $TargetPath = [System.IO.Path]::GetFullPath($TargetPath)
        if ($TargetPath -eq [System.IO.Path]::GetPathRoot($TargetPath))
        {
            throw 'The Canonical target must not be a filesystem root.'
        }
        $TargetPath = $TargetPath.TrimEnd([char[]] '\/')
    }
    elseif ($oneDriveCandidate.Count -gt 1)
    {
        if ($NonInteractive)
        {
            throw 'Multiple OneDrive accounts detected. Specify -TargetPath to select the Canonical target without prompting.'
        }

        $choice = @($oneDriveCandidate.Keys)

        $promptLine = for ($index = 0; $index -lt $choice.Count; $index++)
        {
            "  [$($index + 1)] $($choice[$index]) - $($oneDriveCandidate[$choice[$index]])"
        }

        $prompt = @(
            'Multiple OneDrive accounts detected:'
            $promptLine
            "Select OneDrive account (1-$($choice.Count))"
        ) -join [System.Environment]::NewLine

        do
        {
            $selection = Read-Host -Prompt $prompt
        }
        while ($selection -notmatch '^\d+$' -or [System.Int32] $selection -lt 1 -or [System.Int32] $selection -gt $choice.Count)

        $oneDriveRoot = $oneDriveCandidate[$choice[[System.Int32] $selection - 1]]
    }
    elseif ($oneDriveCandidate.Count -eq 1)
    {
        $oneDriveRoot = @($oneDriveCandidate.Values)[0]
    }
    elseif ($env:OneDrive -and (Test-Path -LiteralPath $env:OneDrive))
    {
        $oneDriveRoot = $env:OneDrive
    }
    else
    {
        $defaultOneDrivePath = Join-Path -Path $userHome -ChildPath 'OneDrive'

        if (Test-Path -LiteralPath $defaultOneDrivePath)
        {
            $oneDriveRoot = $defaultOneDrivePath
        }
    }

    $targetPath = if ($PSBoundParameters.ContainsKey('TargetPath'))
    {
        $TargetPath
    }
    elseif ($oneDriveRoot)
    {
        Join-Path -Path $oneDriveRoot -ChildPath $TargetName
    }
    else
    {
        Join-Path -Path $userHome -ChildPath $TargetName
    }

    $settingsDirectory = Join-Path -Path (Join-Path -Path $configRoot -ChildPath 'Code') -ChildPath 'User'

    $linkItemType = 'SymbolicLink'

    if ($isWindowsPlatform)
    {
        $linkItemType = 'Junction'
    }

    return [PSCustomObject] @{
        UserHome               = $userHome
        ConfigRoot             = $configRoot
        SettingsDirectory      = $settingsDirectory
        SettingsPath           = Join-Path -Path $settingsDirectory -ChildPath 'settings.json'
        KeybindingsPath        = Join-Path -Path $settingsDirectory -ChildPath 'keybindings.json'
        OneDriveRoot           = $oneDriveRoot
        TargetName             = $TargetName
        TargetPath             = $targetPath
        DeploymentManifestPath = Join-Path -Path $targetPath -ChildPath '.copilotatelier.json'
        LegacyLocalPath        = Join-Path -Path $userHome -ChildPath $TargetName
        CopilotRoot            = Join-Path -Path $userHome -ChildPath '.copilot'
        IsWindowsPlatform      = $isWindowsPlatform
        LinkItemType           = $linkItemType
    }
}
