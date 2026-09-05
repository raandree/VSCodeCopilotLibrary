function Get-CopilotAtelierDeploymentPlan
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Directory
    )

    $contentRootPath = [System.IO.Path]::GetFullPath($ContentPath).TrimEnd([char[]] '\/')
    $targetRootPath = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd([char[]] '\/')
    $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    if ([string]::Equals($contentRootPath, $targetRootPath, $comparison) -or
        $contentRootPath.StartsWith($targetRootPath + $separator, $comparison) -or
        $targetRootPath.StartsWith($contentRootPath + $separator, $comparison))
    {
        throw 'ContentPath and the Canonical target overlap. Keep the source tree outside the deployment tree.'
    }

    $record = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath
    $previousFile = @{}
    foreach ($file in $record.Files)
    {
        $previousFile[$file.Path] = $file.Sha256
    }

    $files = [System.Collections.Generic.List[object]]::new()
    $actions = [System.Collections.Generic.List[object]]::new()
    $unownedFiles = [System.Collections.Generic.List[string]]::new()
    $incomingPath = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($directoryName in $Directory.Keys)
    {
        $sourceRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $ContentPath -ChildPath $Directory[$directoryName])).TrimEnd([char[]] '\/')
        $destinationRoot = Join-Path -Path $TargetPath -ChildPath $directoryName
        Assert-CopilotAtelierRegularPath -LiteralPath $sourceRoot -RootPath $ContentPath
        Assert-CopilotAtelierRegularPath -LiteralPath $destinationRoot -RootPath $TargetPath
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container))
        {
            continue
        }

        $pendingDirectory = [System.Collections.Generic.Stack[string]]::new()
        $pendingDirectory.Push($sourceRoot)
        while ($pendingDirectory.Count -gt 0)
        {
            foreach ($item in Get-ChildItem -LiteralPath $pendingDirectory.Pop() -Force -ErrorAction Stop)
            {
                if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint))
                {
                    throw "Refusing reparse point in payload '$($item.FullName)'."
                }
                if ($item.PSIsContainer)
                {
                    $pendingDirectory.Push($item.FullName)
                    continue
                }

                $relativePath = $directoryName + '/' + $item.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/')
                if (-not $incomingPath.Add($relativePath))
                {
                    throw "Deployment conflict: duplicate payload path '$relativePath'."
                }

                $destination = Join-Path -Path $TargetPath -ChildPath $relativePath
                Assert-CopilotAtelierRegularPath -LiteralPath $destination -RootPath $TargetPath
                $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $currentHash = $null
                if (Test-Path -LiteralPath $destination)
                {
                    if (-not (Test-Path -LiteralPath $destination -PathType Leaf))
                    {
                        throw "Deployment conflict: '$relativePath' is not a regular file."
                    }
                    $currentHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
                    if ($currentHash -ne $hash -and $currentHash -ne $previousFile[$relativePath])
                    {
                        throw "Deployment conflict: '$relativePath' has local or untracked changes. Reconcile it before installing; -Force does not overwrite it."
                    }
                }

                if ($currentHash -eq $hash -and -not $previousFile.ContainsKey($relativePath))
                {
                    $unownedFiles.Add($relativePath)
                    continue
                }

                $files.Add([pscustomobject]@{ Path = $relativePath; Sha256 = $hash })
                if ($currentHash -ne $hash)
                {
                    $actions.Add([pscustomobject]@{ Action = 'Copy'; Path = $relativePath; SourcePath = $item.FullName; Sha256 = $hash; PreviousSha256 = $currentHash })
                }
            }
        }
    }

    foreach ($relativePath in $previousFile.Keys)
    {
        if ($incomingPath.Contains($relativePath))
        {
            continue
        }
        $destination = Join-Path -Path $TargetPath -ChildPath $relativePath
        if (Test-Path -LiteralPath $destination)
        {
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
                (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash -ne $previousFile[$relativePath])
            {
                throw "Deployment conflict: retired file '$relativePath' has local changes."
            }
            $actions.Add([pscustomobject]@{ Action = 'Remove'; Path = $relativePath; SourcePath = $null; Sha256 = $previousFile[$relativePath]; PreviousSha256 = $previousFile[$relativePath] })
        }
    }

    [pscustomobject]@{
        Files = @($files | Sort-Object -Property Path)
        Actions = @($actions)
        UnownedFiles = @($unownedFiles)
    }
}
