# Hooks

Deterministic guardrails that run at fixed points in the agent loop. Unlike an
Instruction, a hook does not depend on the model choosing to obey it: VS Code
executes the command and honours its exit code.

Setup deploys this folder to the Canonical target and links it to
`~/.copilot/hooks`. Hook discovery and event behavior are client-specific;
verify loading in the client being used rather than assuming cross-client parity.

## Contents

| File | Event | Purpose |
|---|---|---|
| [`hooks.json`](hooks.json) | — | Hook configuration loaded by VS Code |
| [`scripts/Block-RemoteMutation.ps1`](scripts/Block-RemoteMutation.ps1) | `PreToolUse` | Blocks remote-mutating and irreversible commands |
| [`scripts/Add-SessionContext.ps1`](scripts/Add-SessionContext.ps1) | `SessionStart` | Probes for the Memory Bank, injects the UTC timestamp, starts the session clock |
| [`scripts/Write-SessionClose.ps1`](scripts/Write-SessionClose.ps1) | `Stop` | Advances the session clock's turn counter |
| [`scripts/Get-SessionElapsed.ps1`](scripts/Get-SessionElapsed.ps1) | — | Agent-run reader that prints the Post-flight elapsed line |
| [`scripts/Write-CompactionCheckpoint.ps1`](scripts/Write-CompactionCheckpoint.ps1) | `PreCompact` | Anchors the session on disk before context is truncated |

## Block-RemoteMutation

Inspects any tool input that carries executable command text — `command`,
`commandLine`, `cmd`, `script`, `args`, or `arguments`, at any nesting depth —
rather than deciding from the tool name, so an executor whose name contains no
shell keyword is still covered. It blocks a command that pushes to a git remote,
passes `--no-verify`, runs `git reset --hard`, force-cleans untracked files
(a `-n` dry run is allowed), mutates a pull request, issue, release, repository,
workflow, secret, or cache through the GitHub CLI, or calls `gh api` with a
mutating method or a GraphQL mutation. Shell line continuations are folded first
so a split command cannot hide the subcommand.

Each git rule anchors on the subcommand position, so a branch name, commit
message, or `--grep` value that merely contains the word does not trip it. A
tool with no command-bearing field exits `0` immediately, so editing a document
that mentions `git push` is never blocked. The reason goes to standard error and
the script exits with `2`, which VS Code treats as a blocking error and shows to
the model.

### Authorizing a remote mutation

The house rules allow a push when the user asks for it in the current turn. Set
the escape hatch for that command:

```powershell
$env:COPILOT_ATELIER_ALLOW_REMOTE = '1'
```

Unset it afterwards. The hook records every override on standard error.

## Add-SessionContext

Resolves the session working directory from the hook payload, probes for
`.memory-bank/index.md`, and returns an authoritative statement of whether a
Memory Bank exists, plus the current UTC timestamp. This removes the recurring
failure where an agent concludes "no Memory Bank" from the workspace summary,
which omits dotfile folders.

It also starts the session clock described below, and hands the agent the
absolute path of `Get-SessionElapsed.ps1`. The agent cannot resolve that path
itself — the script sits under `~/.copilot` when deployed and under the plugin
root when installed as a plugin, which is the probe `hooks.json` already carries.

### Session context budget

Injected context defaults to a 4096-character limit. Set
`COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS` to an integer from 1024 through
16384 to change it; invalid values use the default. Oversized paths are omitted
before any lifecycle guidance, and the clock still runs. This is a character
budget for one hook, not a token count or a live context-window estimate.

There is no master-off profile: all four shipped hooks serve lifecycle or
safety obligations. The context budget never disables remote-mutation checks.
Do not persist `COPILOT_ATELIER_ALLOW_REMOTE` in hook configuration; it remains
a per-command authorization supplied only after the user's current request.

## The session clock

Post-flight closes every reply with the elapsed duration of the chat. A model has
no clock: a duration it composes is a guess, and after a compaction it no longer
knows when the session began. So the number is measured on disk and read back.

Three pieces share one clock file:

| Field | Written by | Meaning |
|---|---|---|
| `startedUtc` | `SessionStart` | Round-trip timestamp the duration is measured from |
| `workspace` | `SessionStart` | Working directory the session was opened in |
| `turns` | `Stop` | Turns closed so far in this session |
| `lastTurnEndedUtc` | `Stop` | End of the most recent turn |

It lives at `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json` —
`%LOCALAPPDATA%` on Windows, `~/.local/share` on Linux, `~/Library/Application
Support` on macOS. Not the temp directory: `/tmp` is world-writable, and a
predictable name there invites another local account to pre-create the path. The
`<key>` is the payload's `session_id` with every character that could traverse a
directory stripped, falling back to a hash of the working directory so two
concurrent windows do not share one clock.

### Write-SessionClose

The `Stop` hook advances `turns` and records `lastTurnEndedUtc`. It reports
nothing on the happy path. It used to append the duration itself, but VS Code
renders a hook `systemMessage` as a detached, collapsed warning box rather than
part of the reply, so the line the user actually wanted in the checklist was
never in it. Moving the measurement to the agent put it there; leaving the hook
line in as well would only have added a second copy on every turn.

It still speaks up when the clock cannot be read, because that is the one case
where the agent's own line could not be measured either:

```text
POST-FLIGHT clock - no readable session clock, so the elapsed line reads unavailable.
```

The hook emits no `decision` field. Blocking a `Stop` restarts the agent and
bills another turn, which is far too much to pay for a timestamp. Every failure
path still exits `0`.

A `Stop` that fires while `stop_hook_active` is `true` closes a turn some other
blocking hook already resumed, so it does not advance the turn counter.

### Get-SessionElapsed

Not a hook — the agent runs it as the last action of a turn, which is why it
reports plain text rather than the hook JSON contract. It prints one line, meant
to be copied verbatim as the last line of the reply:

```text
POST-FLIGHT elapsed: 16m (started 09:15 UTC, measured 09:31 UTC, turn 3)
```

Read-only: `Stop` owns `turns`, so the reader reports the turn in progress as one
past the closed count and writes nothing back. Given no `-Path` it picks the
newest clock recorded for the current workspace, which is what survives a
compaction that dropped the injected path. An unreadable clock yields
`POST-FLIGHT elapsed: unavailable (no session clock on disk).` and exit `0`.

## Write-CompactionCheckpoint

Post-flight is an end-of-turn gate, so a long turn that is compacted mid-run
never reaches it and everything the run learned goes with the conversation. This
hook writes `.memory-bank/session/compaction-<UTC>Z.md` before the truncation,
recording the trigger, the transcript path, and the branch, commit, and changed
paths at that moment, followed by a resume protocol.

It writes nothing when the workspace has no Memory Bank — creating one is
reserved for a durable repository write under the `memory-bank` Skill — and
nothing when the payload names no workspace, because falling back to the spawn
directory would drop a checkpoint into an unrelated repository. Every failure
path still exits `0`, so a hook fault never blocks compaction.

`PreCompact` supports the common output format only: there is no
`additionalContext` field, so a hook cannot inject text into the post-compaction
context. The user-visible half is `systemMessage`; the model-facing half is the
compaction-recovery section of
[`rules/preflight.instructions.md`](../rules/preflight.instructions.md),
which survives because Instructions are re-sent with every request.

## Verifying the hooks load

1. Run `Developer: Show Agent Debug Logs` from the Command Palette.
2. Look for `Load Hooks` and confirm `~/.copilot/hooks` is listed.
3. Open the Output panel and select the `GitHub Copilot Chat Hooks` channel to
   read hook output and errors.

## Troubleshooting

- **Hook never fires.** Confirm `hooks.json` is present under
  `~/.copilot/hooks` and that the link resolves. Re-run
  [`Setup-CopilotSettings.ps1`](../../Setup-CopilotSettings.ps1).
- **A workspace `.github/hooks/*.json` never fires.** `chat.hookFilesLocations`
  replaces the default location map rather than extending it. A settings value
  of `{ "~/.copilot/hooks": true }` therefore drops `.github/hooks`, and the
  workspace file loads silently as nothing — no error, no log entry. Add
  `".github/hooks": true` alongside the existing entry, or place the hook in
  `~/.copilot/hooks`. Verified by observing a `Stop` hook that executed only
  after the file moved to the deployed folder.
- **Command not found.** A hook command resolves one of two literal paths: the
  `PLUGIN_ROOT` path supplied by a plugin host or the exact
  `~/.copilot/hooks/scripts` module path. It never scans an agent-plugin
  wildcard. If neither script exists, resolution writes a diagnostic. A missing
  `PreToolUse` guard exits `2` and blocks; missing lifecycle scripts exit `1` so
  they warn without trapping the agent loop. If you deploy the scripts
  elsewhere, replace the resolver in `hooks.json` with one absolute path.
- **The hook dies with a PowerShell parser error.** VS Code hands the command to
  a PowerShell shell, which expands the double-quoted `-Command` argument before
  the child process parses it. A `$` token is therefore consumed by the outer
  shell and reaches the child as an empty string — `$b = if ($env:PLUGIN_ROOT)`
  arrives as `= if ()` and fails with `An expression was expected after '('`.
  Every shipped command is written without a single `$`: paths come from
  `[Environment]::GetEnvironmentVariable(...)` and the blocking exit code from
  `Get-Variable -Name LASTEXITCODE -ValueOnly`. Keep it that way, or the hook
  silently stops guarding anything.
- **Timeout.** These hooks declare 20 seconds. The configuration gate accepts
  explicit limits from 1 through 30 seconds. Investigate slow filesystem access
  before changing the limit; do not replace a bounded hook with an unlimited one.
- **Deployment drift.** Run `(Test-CopilotAtelier).Checks` to inspect missing
  scripts, changed files, and Discovery targets. This is read-only and never
  executes a hook as a health check.

## Safety

The `PreToolUse` block is pattern matching over the command string, not a
sandbox. An obfuscated or indirectly invoked push can evade it. Treat it as
defense in depth that removes the accidental path; [`AGENTS.md`](../../AGENTS.md)
still carries the rule itself.

An agent that can edit these scripts can rewrite its own guardrails. Keep the
hook scripts outside the agent's auto-approved edit scope with
`chat.tools.edits.autoApprove` so a change requires manual approval.

## See also

- [Agent hooks in VS Code](https://code.visualstudio.com/docs/agent-customization/hooks)
- [Hooks reference](https://code.visualstudio.com/docs/agents/reference/hooks-reference)
- [`AGENTS.md`](../../AGENTS.md) — the house rules these hooks enforce
