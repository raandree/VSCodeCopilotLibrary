function Assert-CopilotAtelierDeploymentPath
{
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Path
    )

    $segments = $Path.Split('/')
    if ($segments.Count -lt 2 -or @('agents', 'instructions', 'skills', 'prompts', 'hooks') -cnotcontains $segments[0] -or
        $Path -match '[\\:\x00-\x1f<>"|?*]')
    {
        throw "Invalid Deployment record path '$Path'."
    }

    foreach ($segment in $segments)
    {
        if (-not $segment -or $segment -eq '.' -or $segment -eq '..' -or $segment.Length -gt 255 -or
            $segment -match '[. ]$' -or $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$')
        {
            throw "Invalid Deployment record path '$Path'."
        }
    }
}