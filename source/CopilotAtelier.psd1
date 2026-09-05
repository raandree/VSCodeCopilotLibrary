@{
    RootModule        = 'CopilotAtelier.psm1'

    # Replaced at build time by GitVersion.
    ModuleVersion     = '0.0.1'

    GUID              = '67bbef0b-f4de-4c1b-bb5a-b34104beb5b7'

    Author            = 'raandree'

    CompanyName       = 'raandree'

    Copyright         = '(c) raandree. All rights reserved.'

    Description       = 'Portable GitHub Copilot customization library. Ships custom agents, auto-applied instructions, on-demand skills, prompt templates, and lifecycle hooks, and installs them into the well-known ~/.copilot discovery folders that VS Code, the GitHub Copilot CLI, and Claude Code read.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-CopilotAtelierVersion'
        'Install-CopilotAtelier'
        'Test-CopilotAtelier'
        'Uninstall-CopilotAtelier'
        'Update-CopilotAtelier'
    )

    CmdletsToExport   = @()

    VariablesToExport = @()

    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @(
                'Copilot'
                'GitHubCopilot'
                'VSCode'
                'Agents'
                'Skills'
                'Prompts'
                'Instructions'
                'Hooks'
                'AI'
                'Windows'
                'Linux'
                'MacOS'
            )

            LicenseUri   = 'https://github.com/raandree/CopilotAtelier/blob/main/LICENSE'

            ProjectUri   = 'https://github.com/raandree/CopilotAtelier'

            IconUri      = 'https://raw.githubusercontent.com/raandree/CopilotAtelier/main/assets/CA-glyph-on-light.png'

            Prerelease   = ''

            ReleaseNotes = ''
        }
    }
}
