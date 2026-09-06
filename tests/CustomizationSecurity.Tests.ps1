BeforeAll {
    Import-Module powershell-yaml -ErrorAction Stop
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    function Get-CustomizationSecurityFinding
    {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [ValidateSet('Agent', 'Prompt', 'Hook')]
            [string] $Kind,
            [System.Collections.IDictionary] $Configuration,
            [System.Collections.IDictionary] $Agents = @{}
        )

        $findings = [System.Collections.Generic.List[string]]::new()
        if ($Kind -eq 'Hook')
        {
            if (($Configuration.timeout -isnot [int] -and $Configuration.timeout -isnot [long]) -or
                $Configuration.timeout -lt 1 -or $Configuration.timeout -gt 30)
            {
                $findings.Add('UnboundedHookTimeout')
            }
            foreach ($commandName in @('command', 'windows'))
            {
                if ($Configuration.type -ne 'command' -or
                    $Configuration[$commandName] -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($Configuration[$commandName]))
                {
                    $findings.Add('MissingHookCommand')
                }
                elseif ($Configuration[$commandName] -match '\$\{|\$[A-Za-z_]|%[A-Za-z_][A-Za-z0-9_]*%')
                {
                    $findings.Add('InterpolatedHookCommand')
                }
            }
            if ($Configuration.env -and $Configuration.env.Contains('COPILOT_ATELIER_ALLOW_REMOTE'))
            {
                $findings.Add('PreauthorizedRemoteMutation')
            }
            return $findings
        }

        if ($Kind -eq 'Agent' -and -not $Configuration.Contains('tools'))
        {
            $findings.Add('MissingTools')
        }
        if ($Configuration.Contains('tools'))
        {
            if ($Configuration.tools -is [string] -or $Configuration.tools -is [System.Collections.IDictionary] -or
                $Configuration.tools -isnot [System.Collections.IEnumerable])
            {
                $findings.Add('InvalidTools')
            }
            foreach ($tool in $Configuration.tools)
            {
                if ($tool -isnot [string] -or [string]::IsNullOrWhiteSpace($tool))
                {
                    $findings.Add('InvalidTools')
                }
                elseif ($tool -match '(^|/)\*$')
                {
                    $findings.Add('WildcardTools')
                }
            }
        }

        if ($Kind -eq 'Agent')
        {
            if ($Configuration.tools -contains 'useMcp')
            {
                $findings.Add('UnrestrictedMcp')
            }
            if ($Configuration.tools -contains 'agent')
            {
                if (-not $Configuration.Contains('agents') -or $Configuration.agents -is [string] -or
                    $Configuration.agents -is [System.Collections.IDictionary] -or
                    $Configuration.agents -isnot [System.Collections.IEnumerable] -or $Configuration.agents -contains '*')
                {
                    $findings.Add('UnboundedDelegation')
                }
                else
                {
                    foreach ($delegate in $Configuration.agents)
                    {
                        if ($delegate -isnot [string] -or -not $Agents.Contains($delegate))
                        {
                            $findings.Add('UnknownDelegate')
                        }
                    }
                }
            }
        }
        elseif ($Kind -eq 'Prompt')
        {
            $target = $Configuration.agent
            if (-not $target -or $target -in @('agent', 'ask', 'plan', 'edit'))
            {
                if ($Configuration.Contains('tools') -and @($Configuration.tools).Count -gt 0)
                {
                    $findings.Add('UnverifiablePromptToolBoundary')
                }
            }
            elseif ($target -isnot [string] -or -not $Agents.Contains($target))
            {
                $findings.Add('UnknownPromptAgent')
            }
            elseif ($Configuration.Contains('tools'))
            {
                foreach ($tool in $Configuration.tools)
                {
                    if ($tool -notin $Agents[$target].tools)
                    {
                        $findings.Add('PromptToolExpansion')
                    }
                }
            }
        }
        return $findings
    }

    function Get-SecurityFrontmatter
    {
        param([string] $Path)
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $match = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)')
        if (-not $match.Success) { throw "Missing frontmatter in '$Path'." }
        ConvertFrom-Yaml -Yaml $match.Groups[1].Value -ErrorAction Stop
    }

    function Get-SecurityHookConfiguration
    {
        param([string] $Path)
        $configuration = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($configuration -isnot [pscustomobject] -or $configuration.hooks -isnot [pscustomobject])
        {
            throw 'Hook JSON must contain a hooks object.'
        }
        $hooks = @{}
        foreach ($hookEvent in $configuration.hooks.PSObject.Properties)
        {
            if ($hookEvent.Value -isnot [array]) { throw 'Hook events must contain arrays.' }
            $hooks[$hookEvent.Name] = @(foreach ($hook in $hookEvent.Value)
            {
                if ($hook -isnot [pscustomobject]) { throw 'Hook commands must be objects.' }
                $command = @{}
                foreach ($property in $hook.PSObject.Properties)
                {
                    $command[$property.Name] = $property.Value
                }
                if ($command.env -is [pscustomobject])
                {
                    $environment = @{}
                    foreach ($property in $command.env.PSObject.Properties)
                    {
                        $environment[$property.Name] = $property.Value
                    }
                    $command.env = $environment
                }
                $command
            })
        }
        return $hooks
    }

    $script:agents = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'com.github.copilot/agents') -Filter '*.agent.md' -File)
    {
        $configuration = Get-SecurityFrontmatter -Path $file.FullName
        $script:agents[$configuration.name] = $configuration
    }
}

Describe 'Customization security gate discrimination' -Tag 'Unit' {
    It 'rejects a nonempty tool override for the <Target> Prompt target' -ForEach @(
        @{ Target = 'agent' }
        @{ Target = 'ask' }
        @{ Target = 'plan' }
        @{ Target = 'edit' }
        @{ Target = 'implicit' }
    ) {
        $configuration = @{ tools = @('execute/runInTerminal') }
        if ($Target -ne 'implicit') { $configuration.agent = $Target }

        @(Get-CustomizationSecurityFinding -Kind Prompt -Configuration $configuration) |
            Should -Contain 'UnverifiablePromptToolBoundary'
    }

    It 'accepts inherited or explicitly empty tools for the <Target> Prompt target without asserting a runtime boundary' -ForEach @(
        @{ Target = 'agent' }
        @{ Target = 'ask' }
        @{ Target = 'plan' }
        @{ Target = 'edit' }
        @{ Target = 'implicit' }
    ) {
        $configuration = @{}
        if ($Target -ne 'implicit') { $configuration.agent = $Target }
        @(Get-CustomizationSecurityFinding -Kind Prompt -Configuration $configuration) | Should -HaveCount 0
        $configuration.tools = @()
        @(Get-CustomizationSecurityFinding -Kind Prompt -Configuration $configuration) | Should -HaveCount 0
    }

    It 'rejects an unknown named Prompt target' {
        @(Get-CustomizationSecurityFinding -Kind Prompt -Configuration @{ agent = 'missing-agent'; tools = @('read/readFile') }) |
            Should -Contain 'UnknownPromptAgent'
    }

    It 'rejects invalid hook JSON root or event shape <Text>' -ForEach @(
        @{ Text = 'null' }
        @{ Text = '[]' }
        @{ Text = '{"hooks":[]}' }
        @{ Text = '{"hooks":{"Stop":{}}}' }
    ) {
        $fixturePath = Join-Path $TestDrive 'invalid-shape-hooks.json'
        $Text | Set-Content -LiteralPath $fixturePath
        { Get-SecurityHookConfiguration -Path $fixturePath } | Should -Throw
    }

    It 'rejects YAML-only hook files that are not JSON' {
        $fixturePath = Join-Path $TestDrive 'yaml-only-hooks.json'
        @('hooks:', '  PreToolUse:', '    - type: command', '      timeout: 20', '      command: pwsh -File hook.ps1', '      windows: powershell -File hook.ps1') |
            Set-Content -LiteralPath $fixturePath

        { Get-SecurityHookConfiguration -Path $fixturePath } | Should -Throw
    }

    It 'preserves hook JSON types and rejects preauthorized remote mutation' {
        $fixturePath = Join-Path $TestDrive 'valid-hooks.json'
        '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"pwsh -File hook.ps1","windows":"powershell -File hook.ps1","env":{"COPILOT_ATELIER_ALLOW_REMOTE":"1"}}]}}' |
            Set-Content -LiteralPath $fixturePath

        $configuration = Get-SecurityHookConfiguration -Path $fixturePath

        @($configuration.PreToolUse).Count | Should -Be 1
        $configuration.PreToolUse[0].timeout | Should -Be 20
        @(Get-CustomizationSecurityFinding -Kind Hook -Configuration $configuration.PreToolUse[0]) | Should -Contain 'PreauthorizedRemoteMutation'
    }

    It 'rejects <Code> in <Kind> configuration' -ForEach @(
        @{ Kind = 'Agent'; Code = 'MissingTools'; Configuration = @{ agents = @() } }
        @{ Kind = 'Agent'; Code = 'InvalidTools'; Configuration = @{ tools = 'read/readFile'; agents = @() } }
        @{ Kind = 'Agent'; Code = 'WildcardTools'; Configuration = @{ tools = @('*'); agents = @() } }
        @{ Kind = 'Agent'; Code = 'UnboundedDelegation'; Configuration = @{ tools = @('agent') } }
        @{ Kind = 'Agent'; Code = 'UnboundedDelegation'; Configuration = @{ tools = @('agent'); agents = @('*') } }
        @{ Kind = 'Agent'; Code = 'UnknownDelegate'; Configuration = @{ tools = @('agent'); agents = @('missing-agent') } }
        @{ Kind = 'Agent'; Code = 'UnrestrictedMcp'; Configuration = @{ tools = @('useMcp'); agents = @() } }
        @{ Kind = 'Prompt'; Code = 'PromptToolExpansion'; Configuration = @{ agent = 'worker'; tools = @('execute/runInTerminal') } }
        @{ Kind = 'Hook'; Code = 'UnboundedHookTimeout'; Configuration = @{ type = 'command'; timeout = 0; command = 'pwsh -File hook.ps1'; windows = 'powershell -File hook.ps1' } }
        @{ Kind = 'Hook'; Code = 'UnboundedHookTimeout'; Configuration = @{ type = 'command'; timeout = 31; command = 'pwsh -File hook.ps1'; windows = 'powershell -File hook.ps1' } }
        @{ Kind = 'Hook'; Code = 'UnboundedHookTimeout'; Configuration = @{ type = 'command'; timeout = '20'; command = 'pwsh -File hook.ps1'; windows = 'powershell -File hook.ps1' } }
        @{ Kind = 'Hook'; Code = 'MissingHookCommand'; Configuration = @{ type = 'command'; timeout = 20; command = 'pwsh -File hook.ps1' } }
        @{ Kind = 'Hook'; Code = 'InterpolatedHookCommand'; Configuration = @{ type = 'command'; timeout = 20; command = 'pwsh -Command "$env:USERPROFILE"'; windows = 'powershell -File hook.ps1' } }
        @{ Kind = 'Hook'; Code = 'PreauthorizedRemoteMutation'; Configuration = @{ type = 'command'; timeout = 20; command = 'pwsh -File hook.ps1'; windows = 'powershell -File hook.ps1'; env = @{ COPILOT_ATELIER_ALLOW_REMOTE = '1' } } }
    ) {
        $knownAgents = @{ worker = @{ tools = @('read/readFile'); agents = @() } }
        @(Get-CustomizationSecurityFinding -Kind $Kind -Configuration $Configuration -Agents $knownAgents) | Should -Contain $Code
    }

    It 'accepts bounded read-only agents and narrower Prompt tools' {
        $knownAgents = @{ worker = @{ tools = @('read/readFile', 'search/textSearch'); agents = @() } }
        @(Get-CustomizationSecurityFinding -Kind Agent -Configuration $knownAgents.worker -Agents $knownAgents) | Should -HaveCount 0
        @(Get-CustomizationSecurityFinding -Kind Prompt -Configuration @{ agent = 'worker'; tools = @('read/readFile') } -Agents $knownAgents) | Should -HaveCount 0
    }
}

Describe 'Shipped Customization security configuration' -Tag 'Unit' {
    BeforeAll {
        $script:unrestrictedMcpBaseline = @(
            'career-coach', 'devops-training-writer', 'legal-researcher', 'qc-inspector',
            'research-analyst', 'security-reviewer', 'software-architect', 'software-engineer',
            'tax-researcher', 'technical-writer', 'training-writer', 'troubleshooter'
        )
    }

    It 'keeps every agent bounded except its explicit shrink-only MCP debt' {
        foreach ($entry in $script:agents.GetEnumerator())
        {
            $findings = @(Get-CustomizationSecurityFinding -Kind Agent -Configuration $entry.Value -Agents $script:agents)
            if ($entry.Key -in $script:unrestrictedMcpBaseline)
            {
                $findings | Should -Contain 'UnrestrictedMcp' -Because "remove resolved debt for $($entry.Key) from the baseline"
                $findings = @($findings | Where-Object { $_ -ne 'UnrestrictedMcp' })
            }
            $findings | Should -HaveCount 0 -Because $entry.Key
        }
        foreach ($name in $script:unrestrictedMcpBaseline)
        {
            $script:agents.ContainsKey($name) | Should -BeTrue -Because 'deleted agents must leave the baseline too'
        }
    }

    It 'checks static Prompt tool bounds for named, built-in, and implicit targets' {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'com.github.copilot/commands') -Filter '*.prompt.md' -File)
        {
            $configuration = Get-SecurityFrontmatter -Path $file.FullName
            @(Get-CustomizationSecurityFinding -Kind Prompt -Configuration $configuration -Agents $script:agents) |
                Should -HaveCount 0 -Because $file.Name
        }
    }

    It 'bounds every shared and agent-scoped hook without preauthorizing remote mutation' {
        $configurations = @(
            Get-SecurityHookConfiguration -Path (Join-Path $script:repoRoot 'com.github.copilot/hooks/hooks.json')
            $script:agents.Values | Where-Object { $_.Contains('hooks') } | ForEach-Object { $_.hooks }
        )
        foreach ($configuration in $configurations)
        {
            foreach ($hookEvent in $configuration.GetEnumerator())
            {
                foreach ($hook in $hookEvent.Value)
                {
                    @(Get-CustomizationSecurityFinding -Kind Hook -Configuration $hook) |
                        Should -HaveCount 0 -Because $hookEvent.Key
                }
            }
        }
    }
}
