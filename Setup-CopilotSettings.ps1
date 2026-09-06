<#
    .SYNOPSIS
        Deploys the Copilot customizations from a repository clone.

    .DESCRIPTION
        Development and clone-based entry point for CopilotAtelier. Dot-sources
        the module commands from source/ and runs Install-CopilotAtelier against
        the repository root, so the customizations in the working tree are
        deployed without building or installing the module first.

        Installed from the PowerShell Gallery, use Install-CopilotAtelier and
        Update-CopilotAtelier instead.

    .PARAMETER TargetPath
        Explicit Canonical target. Bypasses ambiguous OneDrive account selection
        without prompting. Passed through to Install-CopilotAtelier.

    .PARAMETER Repair
        Replaces modified Owned files still present in this clone's payload.
        Their modified content is not backed up. Does not overwrite untracked
        files. Passed through to Install-CopilotAtelier; preview with WhatIf.

    .PARAMETER SkipCopilotCliEnvironment
        Skips the user-scoped COPILOT_ALLOW_ALL configuration. Intended for
        sandboxed tests that must not mutate the host user profile.

    .PARAMETER IncludeClaudeCodeLinks
        Additionally links ~/.claude/skills and ~/.agents/skills to the Skills
        directory so Claude Code and other agentskills.io clients discover the
        same library. Off by default: VS Code reads all three user-level skill
        locations, so enabling this registers every Skill more than once in
        VS Code. Create-only, because an existing path belongs to that tool.

    .PARAMETER Force
        Replaces a discovery folder that already holds real content, after
        merging that content into the canonical target. Without it such a folder
        is left alone and reported, so a first run over an existing profile
        never removes anything the user put there.

    .EXAMPLE
        ./Setup-CopilotSettings.ps1

        Deploys the customizations in this clone and configures VS Code.

    .LINK
        https://github.com/raandree/CopilotAtelier
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param
(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TargetPath,

    [Parameter()]
    [switch]$Repair,

    [Parameter()]
    [switch]$SkipCopilotCliEnvironment,

    [Parameter()]
    [switch]$IncludeClaudeCodeLinks,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'source'

foreach ($scopeName in @('Private', 'Public')) {
    $scopePath = Join-Path -Path $sourcePath -ChildPath $scopeName

    if (-not (Test-Path -LiteralPath $scopePath)) {
        throw "Unable to find the module sources at '$scopePath'."
    }

    Get-ChildItem -LiteralPath $scopePath -Filter '*.ps1' -File |
        ForEach-Object -Process {
            . $_.FullName
        }
}

$installParameter = @{} + $PSBoundParameters
$installParameter['ContentPath'] = $PSScriptRoot

# The script is the interactive entry point, so its progress is always shown.
if (-not $installParameter.ContainsKey('InformationAction')) {
    $installParameter['InformationAction'] = 'Continue'
}

if ($PSCmdlet.ShouldProcess($PSScriptRoot, 'Deploy clone Customizations and configure the client')) {
    Install-CopilotAtelier @installParameter
}
