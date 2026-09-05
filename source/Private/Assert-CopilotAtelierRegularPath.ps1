function Assert-CopilotAtelierRegularPath
{
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $LiteralPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RootPath
    )

    $leafPath = [System.IO.Path]::GetFullPath($LiteralPath)
    $RootPath = [System.IO.Path]::GetFullPath($RootPath)
    if ($leafPath.Length -gt [System.IO.Path]::GetPathRoot($leafPath).Length)
    {
        $leafPath = $leafPath.TrimEnd([char[]] '\/')
    }
    if ($RootPath.Length -gt [System.IO.Path]::GetPathRoot($RootPath).Length)
    {
        $RootPath = $RootPath.TrimEnd([char[]] '\/')
    }
    $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $rootPrefix = $RootPath.TrimEnd([char[]] '\/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not [string]::Equals($leafPath, $RootPath, $comparison) -and -not $leafPath.StartsWith($rootPrefix, $comparison))
    {
        throw "Deployment path '$leafPath' is outside selected root '$RootPath'."
    }
    $currentPath = $leafPath

    while ($currentPath)
    {
        try
        {
            $attributes = [System.IO.File]::GetAttributes($currentPath)
            if ($attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint))
            {
                throw "Refusing reparse point in deployment path '$currentPath'."
            }
            if ($currentPath -ne $leafPath -and -not $attributes.HasFlag([System.IO.FileAttributes]::Directory))
            {
                throw "Deployment conflict: '$currentPath' is not a directory."
            }
        }
        catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException]
        {
            Write-Verbose -Message "Deployment path does not exist yet: $currentPath"
        }

        if ([string]::Equals($currentPath, $RootPath, $comparison))
        {
            break
        }
        $currentPath = [System.IO.Path]::GetDirectoryName($currentPath)
    }
}
