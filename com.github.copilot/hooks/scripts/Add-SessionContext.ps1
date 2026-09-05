<#
.SYNOPSIS
    SessionStart hook that injects the deterministic part of Pre-flight.
.DESCRIPTION
    Reads the VS Code SessionStart hook payload from standard input, resolves the
    session working directory, and returns a short block of additional context on
    standard output: the current UTC timestamp and an authoritative statement of
    whether a Memory Bank exists in the workspace.

    The workspace summary supplied at session start omits dotfile folders, which
    is the recurring cause of agents concluding that no Memory Bank exists. This
    hook probes the filesystem instead of relying on the model to remember to.

    It also starts the session clock: the same timestamp is written to a small
    per-session file under LocalApplicationData, which the Stop hook reads to
    report the elapsed chat duration at the end of every turn. A model cannot
    read a clock, so neither number may be left to it.

    COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS bounds injected context to
    1024-16384 characters (default 4096). Invalid values use the default.
    Long paths are omitted before lifecycle or safety guidance is shortened.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER ClockRoot
    Directory holding the session clock files. Defaults to the per-user
    application data location. Tests override it to stay off the real profile.
.NOTES
    Emits the SessionStart output contract shared by VS Code, Copilot CLI, and
    Claude Code. Always exits 0 so a probe failure never blocks a session.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$InputJson,

    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$ClockRoot
)

function Get-SessionClockPath {
    <#
        Resolves the clock file for a session. Duplicated verbatim in
        Write-SessionClose.ps1: VS Code launches each hook by its own path, so a
        shared helper would need the same fragile path probing that hooks.json
        already carries. Both sides must derive the same name from the same
        payload, so change them together.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$WorkingDirectory,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        # Per-user by construction. The temp directory is world-writable on
        # Linux, where a predictable name invites another local account to
        # pre-create the path.
        $Root = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)

        if ([string]::IsNullOrWhiteSpace($Root)) {
            $Root = [IO.Path]::GetTempPath()
        }

        $Root = [IO.Path]::Combine($Root, 'CopilotAtelier', 'sessions')
    }

    # The payload supplies this value, so it becomes a path component only after
    # every character that could traverse a directory is gone.
    $key = ($SessionId -replace '[^A-Za-z0-9._-]', '')

    if ($key.Length -gt 64) {
        $key = $key.Substring(0, 64)
    }

    if ([string]::IsNullOrWhiteSpace($key)) {
        # No session id: fall back to the workspace so two concurrent windows do
        # not share one clock.
        $seed = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { 'default' } else { $WorkingDirectory }
        $sha = [Security.Cryptography.SHA256]::Create()

        try {
            $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($seed))
        } finally {
            $sha.Dispose()
        }

        $key = 'cwd-' + [BitConverter]::ToString($digest[0..7]).Replace('-', '').ToLowerInvariant()
    }

    return [IO.Path]::Combine($Root, "session-$key.json")
}

if ([string]::IsNullOrEmpty($InputJson)) {
    # Decode explicitly: Windows PowerShell would otherwise use the console input
    # encoding, which mangles non-ASCII payloads that pwsh reads as UTF-8.
    $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
    try {
        $InputJson = $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

$payload = $null
if (-not [string]::IsNullOrWhiteSpace($InputJson)) {
    try {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $payload = $null
    }
}

$workingDirectory = if ($payload) { [string]$payload.cwd } else { $null }

if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
    $workingDirectory = (Get-Location).Path
}

# The path is interpolated into the instruction channel, so strip control
# characters that a hostile workspace name could use to inject extra lines.
$workingDirectory = $workingDirectory -replace '[\p{Cc}]', ' '

<#
    The payload supplies this path, so it is untrusted and may name a drive or a
    shape this host cannot resolve. Combine and probe it through .NET rather than
    the PowerShell provider: a provider that cannot resolve the path writes to
    standard error, and the caller merges the streams, which would corrupt the
    JSON contract on standard output. [System.IO.File]::Exists returns false for
    any path it cannot read and never throws.
#>
$memoryBankExists = $false
$memoryBankIndex = $workingDirectory

try {
    $memoryBankIndex = [System.IO.Path]::Combine($workingDirectory, '.memory-bank', 'index.md')
    $memoryBankExists = [System.IO.File]::Exists($memoryBankIndex)
} catch {
    $memoryBankExists = $false
}

if ($memoryBankExists) {
    $memoryBankState = "A Memory Bank exists at $memoryBankIndex. This probe is authoritative: " +
    'do not conclude that the Memory Bank is absent. Read the index and apply its routing table ' +
    'before the first tool call.'
} else {
    $memoryBankState = "No Memory Bank exists under $workingDirectory. This probe is authoritative. " +
    'Create one only before a durable repository write, using the memory-bank Skill.'
}

$startedUtc = (Get-Date).ToUniversalTime()

<#
    Start the session clock. The Stop hook reads this file at the end of every
    turn to report the elapsed chat duration, and it has to survive compaction,
    which is why it goes to disk rather than into the injected context alone.
    A clock failure must never cost the caller its Memory Bank probe.
#>
try {
    $clockPath = Get-SessionClockPath `
        -SessionId ([string]$payload.session_id) `
        -WorkingDirectory $workingDirectory `
        -Root $ClockRoot

    $clockDirectory = [IO.Path]::GetDirectoryName($clockPath)

    if (-not [IO.Directory]::Exists($clockDirectory)) {
        [IO.Directory]::CreateDirectory($clockDirectory) | Out-Null
    }

    $clock = [ordered]@{
        startedUtc = $startedUtc.ToString('o')
        workspace = $workingDirectory
        turns = 0
    } | ConvertTo-Json -Depth 3

    [IO.File]::WriteAllText($clockPath, $clock, [Text.UTF8Encoding]::new($false))
} catch {
    # A missing clock costs the closing duration line, nothing else. Reporting on
    # any other stream would corrupt the JSON contract on standard output.
    Write-Debug -Message "Session clock not started: $($_.Exception.Message)"
}

<#
    Hand the agent the absolute path of the clock reader. Post-flight closes with
    a measured duration, and the agent cannot resolve the reader itself: it sits
    under ~/.copilot when deployed and under the plugin root when installed as a
    plugin, which is the probe hooks.json already carries.
#>
$elapsedReader = [IO.Path]::Combine($PSScriptRoot, 'Get-SessionElapsed.ps1')

$line = @(
    "Session started at $($startedUtc.ToString('yyyy-MM-dd HH:mm')) UTC."
    $memoryBankState
    'Open the reply with that UTC timestamp and a one-line PRE-FLIGHT acknowledgment.'
    "Close every reply by running & '$elapsedReader' and copying its single line verbatim as the last line of the POST-FLIGHT block."
    'Never push or otherwise mutate a git remote unless the user asks in the current turn.'
)

$contextLimit = 4096
$configuredLimit = 0
if ([int]::TryParse([Environment]::GetEnvironmentVariable('COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS'), [ref]$configuredLimit) -and
    $configuredLimit -ge 1024 -and $configuredLimit -le 16384) {
    $contextLimit = $configuredLimit
}

$additionalContext = $line -join ' '
if ($additionalContext.Length -gt $contextLimit) {
    $line[1] = if ($memoryBankExists) {
        'A Memory Bank exists in the working directory. Read its index and apply its routes before the first tool call.'
    } else {
        'The Memory Bank probe found no index in the working directory. Check before initializing; create only missing files for durable work.'
    }
    $additionalContext = $line -join ' '
}
if ($additionalContext.Length -gt $contextLimit) {
    $line[3] = 'Close every reply with the measured Get-SessionElapsed.ps1 output in POST-FLIGHT. The reader is beside the SessionStart hook.'
    $additionalContext = $line -join ' '
}

$output = [ordered]@{
    continue = $true
    hookSpecificOutput = [ordered]@{
        hookEventName = 'SessionStart'
        additionalContext = $additionalContext
    }
}

$output | ConvertTo-Json -Depth 5 -Compress
exit 0
