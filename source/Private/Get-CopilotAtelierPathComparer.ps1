function Get-CopilotAtelierPathComparer
{
    [CmdletBinding()]
    [OutputType([System.StringComparer])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path
    )

    Assert-CopilotAtelierRegularPath -LiteralPath $Path -RootPath $Path
    $directory = [System.IO.Path]::GetFullPath($Path)
    while ($directory)
    {
        if ([System.IO.Directory]::Exists($directory))
        {
            $entries = [System.IO.Directory]::GetFileSystemEntries($directory)
            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($entry in $entries)
            {
                $null = $names.Add([System.IO.Path]::GetFileName($entry))
            }
            foreach ($name in $names)
            {
                for ($characterIndex = 0; $characterIndex -lt $name.Length; $characterIndex++)
                {
                    $characterCode = [int][char] $name[$characterIndex]
                    if (($characterCode -lt 65 -or $characterCode -gt 90) -and
                        ($characterCode -lt 97 -or $characterCode -gt 122))
                    {
                        continue
                    }
                    $alternateName = $name.Remove($characterIndex, 1).Insert($characterIndex, [string][char]($characterCode -bxor 32))
                    if ($names.Contains($alternateName)) { continue }
                    try
                    {
                        $null = [System.IO.File]::GetAttributes((Join-Path -Path $directory -ChildPath $alternateName))
                        return [System.StringComparer]::OrdinalIgnoreCase
                    }
                    catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException]
                    {
                        return [System.StringComparer]::Ordinal
                    }
                }
            }
        }
        $directory = [System.IO.Path]::GetDirectoryName($directory.TrimEnd([char[]] '\/'))
    }
    throw "Cannot determine the filename comparison policy for '$Path' without a probe file."
}