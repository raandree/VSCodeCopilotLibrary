function Install-CopilotAtelier
{
    <#
        .SYNOPSIS
            Deploys the Copilot customizations and configures the VS Code client.

        .DESCRIPTION
            Copies the Agents, Instructions, Skills, Prompts, and Hooks
            directories to the canonical target, links the well-known
            ~/.copilot discovery folders to that target, merges the VS Code
            settings and keybindings, and records the deployed version and
            SHA-256 of each owned file. Updates preserve user-added files and
            refuse conflicts with locally changed files before writing.

            The canonical target is ~/OneDrive/CopilotAtelier when OneDrive is
            available and ~/CopilotAtelier otherwise. The command is idempotent:
            it removes obsolete location aliases without disturbing user-defined
            entries, tolerates comments in the VS Code configuration files, and
            creates a timestamped backup of every file it rewrites.

            Progress is written to the information stream. Run with
            -InformationAction Continue to see it.

        .PARAMETER ContentPath
            The directory that holds the customization directories. Defaults to
            the module base, or the repository root when the source files are
            dot-sourced during development.

        .PARAMETER SkipCopilotCliEnvironment
            Skips the user-scoped COPILOT_ALLOW_ALL configuration. Intended for
            sandboxed tests that must not mutate the host user profile.

        .PARAMETER IncludeClaudeCodeLinks
            Additionally links ~/.claude/skills and ~/.agents/skills to the
            Skills directory so Claude Code and other agentskills.io clients
            discover the same library. Off by default: VS Code reads all three
            user-level skill locations, so enabling this registers every Skill
            more than once in VS Code. Create-only, because an existing path
            belongs to that other tool.

        .PARAMETER Force
            Replaces a discovery folder that already holds real content, after
            merging that content into the canonical target. Without it such a
            folder is left alone and reported, so a first run over an existing
            profile never removes anything the user put there. A child that
            differs from the target's copy, or that is or contains a reparse
            point, still stops the merge and is reported.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Install-CopilotAtelier -InformationAction Continue

            Deploys the customizations and prints each step.

        .EXAMPLE
            Install-CopilotAtelier -IncludeClaudeCodeLinks

            Also exposes the Skills directory to Claude Code.

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
        $ContentPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipCopilotCliEnvironment,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IncludeClaudeCodeLinks,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('ContentPath'))
    {
        $ContentPath = Get-CopilotAtelierContentPath
    }

    $ContentPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContentPath)

    <#
        Deployed directory name -> source path inside the content root. Every
        Copilot-specific component lives under the Agent Plugins 1.0 client
        extension namespace, where the format names them rules and commands, so
        the source layout no longer matches the deployed layout.
    #>
    $customizationDirectory = [ordered] @{
        agents       = 'com.github.copilot/agents'
        instructions = 'com.github.copilot/rules'
        skills       = 'skills'
        prompts      = 'com.github.copilot/commands'
        hooks        = 'com.github.copilot/hooks'
    }

    $presentDirectory = @(
        $customizationDirectory.Keys |
            Where-Object -FilterScript {
                Test-Path -LiteralPath (Join-Path -Path $ContentPath -ChildPath $customizationDirectory[$_]) -PathType Container
            }
    )

    if (-not $presentDirectory)
    {
        throw "No customization directory found under '$ContentPath'. Expected at least one of: $($customizationDirectory.Keys -join ', ')."
    }

    $path = Get-CopilotAtelierPath
    $deploymentPlan = Get-CopilotAtelierDeploymentPlan -ContentPath $ContentPath -TargetPath $path.TargetPath -Directory $customizationDirectory
    if ($deploymentPlan.UnownedFiles.Count -gt 0)
    {
        Write-Warning -Message "Preserved $($deploymentPlan.UnownedFiles.Count) matching untracked file(s) without claiming ownership. Uninstall will leave them untouched."
    }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    if (-not (Test-Path -LiteralPath $path.SettingsDirectory))
    {
        New-Item -ItemType Directory -Path $path.SettingsDirectory -Force | Out-Null

        Write-Information -MessageData "Created VS Code User directory: $($path.SettingsDirectory)"
    }

    if (-not (Test-Path -LiteralPath $path.SettingsPath))
    {
        Write-Information -MessageData "VS Code settings file not found at $($path.SettingsPath) - creating a new one."

        '{}' | Set-Content -LiteralPath $path.SettingsPath -Encoding UTF8

        $settingsText = '{}'
    }
    else
    {
        $settingsBackupPath = '{0}.{1}.bak' -f $path.SettingsPath, $timestamp

        Copy-Item -LiteralPath $path.SettingsPath -Destination $settingsBackupPath -Force

        Write-Information -MessageData "Backup created: $settingsBackupPath"

        $settingsText = Get-Content -LiteralPath $path.SettingsPath -Raw
    }

    $settings = ConvertFrom-Jsonc -Text $settingsText

    if ($null -eq $settings)
    {
        $settings = [PSCustomObject] @{}
    }

    if ($path.OneDriveRoot)
    {
        Write-Information -MessageData "OneDrive detected at: $($path.OneDriveRoot) - target tree will live there."
    }
    else
    {
        Write-Information -MessageData "OneDrive not found - target tree will live under $($path.TargetPath)."
    }

    <#
        Remove aliases written by releases that predate ~/.copilot discovery.
        Unrelated locations remain available to the user.
    #>
    $legacyLocationSetting = [ordered] @{
        'chat.agentFilesLocations'        = 'Agents'
        'chat.instructionsFilesLocations' = 'Instructions'
        'chat.agentSkillsLocations'       = 'Skills'
        'chat.promptFilesLocations'       = 'Prompts'
    }

    foreach ($location in $legacyLocationSetting.GetEnumerator())
    {
        $removeLocationSettingEntry = @{
            Settings     = $settings
            PropertyName = $location.Key
            Entry        = @(
                '~/{0}/{1}' -f $path.TargetName, $location.Value
                '~/OneDrive/{0}/{1}' -f $path.TargetName, $location.Value
            )
        }

        Remove-LocationSettingEntry @removeLocationSettingEntry
    }

    <#
        `github.copilot.advanced` is the completions bag and has no documented
        `model` member, so earlier releases wrote a value Copilot never consumed.
    #>
    $settings.PSObject.Properties.Remove('github.copilot.advanced.model')

    $settingValue = [ordered] @{
        'chat.includeApplyingInstructions'               = $true
        'chat.includeReferencedInstructions'             = $true
        'gitlens.ai.vscode.model'                        = 'copilot:claude-opus-5'
        'github.copilot.chat.agent.thinkingTool'         = $true
        'github.copilot.chat.search.semanticTextResults' = $true
        'github.copilot.chat.skillTool.enabled'          = $true
        'github.copilot.chat.agent.maxRequests'          = 500
    }

    foreach ($setting in $settingValue.GetEnumerator())
    {
        $settings |
            Add-Member -NotePropertyName $setting.Key -NotePropertyValue $setting.Value -Force
    }

    <#
        Unlike agents, instructions, skills, and hooks, the chat extension does
        not auto-discover ~/.copilot/prompts - it reads the per-profile prompts
        folder plus the paths listed in this setting. Merge so user-added prompt
        locations survive.
    #>
    Merge-LocationSetting -Settings $settings -PropertyName 'chat.promptFilesLocations' -NewEntry @{
        '~/.copilot/prompts' = $true
    }

    <#
        ~/.copilot/hooks is a well-known user location, but naming it explicitly
        keeps discovery working if the implicit default changes.
    #>
    Merge-LocationSetting -Settings $settings -PropertyName 'chat.hookFilesLocations' -NewEntry @{
        '~/.copilot/hooks' = $true
    }

    if ($PSCmdlet.ShouldProcess($path.SettingsPath, 'Write VS Code settings'))
    {
        $settings |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $path.SettingsPath -Encoding UTF8
    }

    if ($path.OneDriveRoot -and (Test-Path -LiteralPath $path.LegacyLocalPath))
    {
        Write-Warning -Message "Preserved legacy local tree '$($path.LegacyLocalPath)': ownership cannot be assumed."
    }

    foreach ($directoryName in $customizationDirectory.Keys)
    {
        $destination = Join-Path -Path $path.TargetPath -ChildPath $directoryName
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }

    foreach ($action in $deploymentPlan.Actions)
    {
        $destination = Join-Path -Path $path.TargetPath -ChildPath $action.Path
        if ($PSCmdlet.ShouldProcess($destination, "$($action.Action) owned Customization file"))
        {
            Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $path.TargetPath
            $currentHash = if (Test-Path -LiteralPath $destination)
            {
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            }
            else
            {
                $null
            }
            if ($currentHash -ne $action.PreviousSha256)
            {
                throw "Deployment changed during apply: '$($action.Path)'."
            }
            if ($action.Action -eq 'Remove')
            {
                Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
            }
            else
            {
                Assert-CopilotAtelierRegularPath -LiteralPath $action.SourcePath -RootPath $ContentPath
                if ((Get-FileHash -LiteralPath $action.SourcePath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $action.Sha256)
                {
                    throw "Payload changed during deployment: '$($action.Path)'."
                }
                New-Item -ItemType Directory -Path (Split-Path -Path $destination -Parent) -Force | Out-Null
                Copy-Item -LiteralPath $action.SourcePath -Destination $destination -Force -ErrorAction Stop
                if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash -ne $action.Sha256)
                {
                    throw "Deployment verification failed for '$($action.Path)'."
                }
            }
        }
    }

    $moduleVersion = $ExecutionContext.SessionState.Module.Version
    $deployedVersion = $null

    if ($moduleVersion)
    {
        $deployedVersion = $moduleVersion.ToString()
    }

    $deployment = [PSCustomObject] @{
        SchemaVersion = 1
        Version     = $deployedVersion
        InstalledOn = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        ContentPath = $ContentPath
        Files       = @($deploymentPlan.Files)
    }

    if ($PSCmdlet.ShouldProcess($path.DeploymentManifestPath, 'Record the deployed version'))
    {
        $deployment |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $path.DeploymentManifestPath -Encoding UTF8
    }

    foreach ($directoryName in $customizationDirectory.Keys)
    {
        $setCustomizationLink = @{
            LinkPath     = Join-Path -Path $path.CopilotRoot -ChildPath $directoryName
            TargetPath   = Join-Path -Path $path.TargetPath -ChildPath $directoryName
            LinkItemType = $path.LinkItemType
            Force        = $Force
        }

        Set-CustomizationLink @setCustomizationLink
    }

    <#
        Opt-in and create-only. VS Code reads ~/.copilot/skills, ~/.claude/skills,
        and ~/.agents/skills, so these links register every Skill more than once
        in VS Code. An existing path belongs to that other tool: adopting it would
        take over the user's own skills without a separate ownership decision.
    #>
    if ($IncludeClaudeCodeLinks)
    {
        Write-Information -MessageData 'Claude Code links requested: VS Code will register Skills from more than one location.'

        $claudeCodeLinkPath = @(
            Join-Path -Path (Join-Path -Path $path.UserHome -ChildPath '.claude') -ChildPath 'skills'
            Join-Path -Path (Join-Path -Path $path.UserHome -ChildPath '.agents') -ChildPath 'skills'
        )

        foreach ($linkPath in $claudeCodeLinkPath)
        {
            $setCustomizationLink = @{
                LinkPath     = $linkPath
                TargetPath   = Join-Path -Path $path.TargetPath -ChildPath 'skills'
                LinkItemType = $path.LinkItemType
                CreateOnly   = $true
            }

            Set-CustomizationLink @setCustomizationLink
        }
    }

    <#
        `gh copilot` consults COPILOT_ALLOW_ALL=1 to bypass the per-tool
        confirmation prompts that otherwise block non-interactive use of the
        custom agents and skills. Persisted at User scope so every new shell
        picks it up; the process variable is set too so the change is visible
        without opening a new shell.
    #>
    $copilotEnvironmentName = 'COPILOT_ALLOW_ALL'
    $copilotEnvironmentValue = '1'

    if ($SkipCopilotCliEnvironment)
    {
        Write-Verbose -Message "Skipped environment variable: $copilotEnvironmentName (requested)"
    }
    elseif ($PSCmdlet.ShouldProcess($copilotEnvironmentName, 'Set the Copilot CLI environment variable'))
    {
        $existingValue = [System.Environment]::GetEnvironmentVariable($copilotEnvironmentName, 'User')

        if ($existingValue -eq $copilotEnvironmentValue)
        {
            Write-Information -MessageData "Environment variable already set: $copilotEnvironmentName=$copilotEnvironmentValue (User)"
        }
        else
        {
            [System.Environment]::SetEnvironmentVariable($copilotEnvironmentName, $copilotEnvironmentValue, 'User')

            Write-Information -MessageData "Environment variable set: $copilotEnvironmentName=$copilotEnvironmentValue (User)"
            Write-Information -MessageData '  Open a new shell to pick up the change in other sessions.'
        }

        [System.Environment]::SetEnvironmentVariable($copilotEnvironmentName, $copilotEnvironmentValue, 'Process')
    }

    <#
        Idempotent keybinding merge: match on the (key, command, when) tuple so
        re-runs do not duplicate entries and user-added bindings are preserved.
    #>
    $keybindingSourcePath = Join-Path -Path (Join-Path -Path $ContentPath -ChildPath 'keybindings') -ChildPath 'keybindings.json'

    if (Test-Path -LiteralPath $keybindingSourcePath)
    {
        if (-not (Test-Path -LiteralPath $path.KeybindingsPath))
        {
            Write-Information -MessageData "VS Code keybindings file not found at $($path.KeybindingsPath) - creating a new one."

            '[]' | Set-Content -LiteralPath $path.KeybindingsPath -Encoding UTF8

            $existingKeybindingText = '[]'
        }
        else
        {
            $keybindingBackupPath = '{0}.{1}.bak' -f $path.KeybindingsPath, $timestamp

            Copy-Item -LiteralPath $path.KeybindingsPath -Destination $keybindingBackupPath -Force

            Write-Information -MessageData "Backup created: $keybindingBackupPath"

            $existingKeybindingText = Get-Content -LiteralPath $path.KeybindingsPath -Raw
        }

        $existingKeybindingData = ConvertFrom-Jsonc -Text $existingKeybindingText
        $existingKeybinding = @()

        if ($null -ne $existingKeybindingData)
        {
            $existingKeybinding = @($existingKeybindingData)
        }

        $desiredKeybinding = @(ConvertFrom-Jsonc -Text (Get-Content -LiteralPath $keybindingSourcePath -Raw))

        $desiredKey = @{}

        foreach ($binding in $desiredKeybinding)
        {
            $desiredKey[(Get-KeybindingKey -Binding $binding)] = $true
        }

        <#
            Keep every existing binding that is not one of ours, then append
            ours. Stale copies of our bindings are dropped, so an updated `when`
            clause does not leave a duplicate behind.
        #>
        $preservedKeybinding = @(
            $existingKeybinding |
                Where-Object -FilterScript {
                    -not $desiredKey.ContainsKey((Get-KeybindingKey -Binding $_))
                }
        )

        if ($PSCmdlet.ShouldProcess($path.KeybindingsPath, 'Merge keybindings'))
        {
            @($preservedKeybinding) + @($desiredKeybinding) |
                ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $path.KeybindingsPath -Encoding UTF8
        }

        Write-Information -MessageData "Keybindings merged: $($desiredKeybinding.Count) bindings from the module, $($preservedKeybinding.Count) user bindings preserved."
    }
    else
    {
        Write-Information -MessageData "Skipped keybindings merge: $keybindingSourcePath not found."
    }

    Write-Information -MessageData ''
    Write-Information -MessageData "Settings updated at: $($path.SettingsPath)"
    Write-Information -MessageData 'Restart VS Code to apply changes.'

    return [PSCustomObject] @{
        Version         = $deployment.Version
        TargetPath      = $path.TargetPath
        ContentPath     = $ContentPath
        SettingsPath    = $path.SettingsPath
        KeybindingsPath = $path.KeybindingsPath
        Deployed        = $presentDirectory
    }
}
