function New-CopilotAtelierTestProfile
{
    param([string] $Root, [string] $ProjectPath)

    $original = @{}
    foreach ($name in @('APPDATA', 'HOME', 'USERPROFILE', 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial', 'XDG_CONFIG_HOME'))
    {
        $original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    $homePath = Join-Path $Root 'home'
    $configPath = Join-Path $Root 'config'
    $contentPath = Join-Path $Root 'content'
    New-Item -ItemType Directory -Path $homePath, $configPath -Force | Out-Null
    foreach ($directory in @('com.github.copilot/agents', 'com.github.copilot/rules', 'skills', 'com.github.copilot/commands'))
    {
        $destination = Join-Path $contentPath $directory
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'marker.md') -Value 'owned content'
    }
    Copy-Item -LiteralPath (Join-Path $ProjectPath 'com.github.copilot/hooks') -Destination (Join-Path $contentPath 'com.github.copilot/hooks') -Recurse

    foreach ($name in @('HOME', 'USERPROFILE'))
    {
        [Environment]::SetEnvironmentVariable($name, $homePath, 'Process')
    }
    foreach ($name in @('APPDATA', 'XDG_CONFIG_HOME'))
    {
        [Environment]::SetEnvironmentVariable($name, $configPath, 'Process')
    }
    foreach ($name in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial'))
    {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    [pscustomobject]@{
        Original = $original
        HomePath = $homePath
        ContentPath = $contentPath
        TargetPath = Join-Path $homePath 'CopilotAtelier'
        CopilotRoot = Join-Path $homePath '.copilot'
    }
}

function Restore-CopilotAtelierTestProfile
{
    param([hashtable] $Original)
    foreach ($name in $Original.Keys)
    {
        [Environment]::SetEnvironmentVariable($name, $Original[$name], 'Process')
    }
}

function Import-CopilotAtelierTestModule
{
    param([string] $ProjectPath)
    $manifest = Get-ChildItem -Path (Join-Path $ProjectPath 'output/*/CopilotAtelier/*/CopilotAtelier.psd1') |
        Sort-Object -Property { [version] $_.Directory.Name } -Descending |
        Select-Object -First 1
    Import-Module -Name $manifest.FullName -Force -ErrorAction Stop
}
