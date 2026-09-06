function Enter-CopilotAtelierDeploymentLock
{
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath
    )

    $targetName = (Split-Path -Path $TargetPath -Leaf).ToUpperInvariant()
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $key = [System.BitConverter]::ToString($algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($targetName))).Replace('-', '')
    }
    finally
    {
        $algorithm.Dispose()
    }
    $parentPath = Split-Path -Path $TargetPath -Parent
    $lockPath = Join-Path -Path $parentPath -ChildPath ".copilotatelier-$key.lock"
    Assert-CopilotAtelierRegularPath -LiteralPath $lockPath -RootPath $lockPath
    New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    try
    {
        $handle = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException]
    {
        throw "Deployment is in use or its coordination file cannot be opened: '$TargetPath'. $($_.Exception.Message)"
    }
    if ($handle.Length -ne 0)
    {
        $handle.Dispose()
        throw "Deployment conflict: nonempty coordination file '$lockPath' was left untouched."
    }
    return $handle
}