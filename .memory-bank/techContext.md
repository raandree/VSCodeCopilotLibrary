---
status: current
last-verified: 2026-09-06
owner: software-engineer
source: build.yaml and source/
---

# Tech context

## Technology stack

| Layer | Technology | Purpose |
|---|---|---|
| IDE | VS Code | Primary development environment |
| AI assistant | GitHub Copilot with Claude Opus 5, Opus 4.8 fallback | Code, review, and documentation |
| Sync | OneDrive | Cross-machine Customization distribution |
| Distribution | PowerShell Gallery module `CopilotAtelier` | Versioned install and update |
| Build | Sampler, ModuleBuilder, InvokeBuild | Module build, package, and release |
| Versioning | GitVersion via `GitVersion.yml` | Semantic version from git history |
| CI/CD | GitHub Actions (`.github/workflows/ci.yml`) | Build, cross-platform test, publish |
| Setup | PowerShell 5.1+ | Client configuration and file deployment |
| Version control | Git | Repository history and collaboration |
| Tests | Pester 5 | Setup, module, and Customization regression checks |
| Skill conformance | `uv` fetching upstream `skills-ref` (pinned) | Validates `Skills/*` against the open specification |

`uv` is the only non-PowerShell dependency and it is test-only: without it the
conformance gate skips locally and throws in CI, where the workflow installs it.
Nothing in building, installing, or using the module needs it.

## Module layout

`source/` holds the manifest, the empty root module that ModuleBuilder fills,
five public commands, and private deployment, path, link, JSONC, and keybinding
helpers. `.build/Copy_Customizations_To_Output.build.ps1` copies the root
Customization directories listed in `build.yaml` into the built module at
`output/module/CopilotAtelier/<version>/`.

> Sampler 0.120.0 ships a `WorkspaceDependencies` task whose
> `BuiltModuleSubdirectory` property default is `module`, and InvokeBuild treats
> an empty string as an unset property. That default therefore wins over
> `build.yaml`, so `BuiltModuleSubdirectory` must stay `module` or the built
> module manifest is looked up in the wrong place. Tests match the subdirectory
> rather than hard-coding it.

| Command | Purpose |
|---|---|
| `Install-CopilotAtelier` | Deploy the Customizations, link `~/.copilot`, merge settings and keybindings, write the Deployment record |
| `Update-CopilotAtelier` | Compare against the Gallery, install a newer version, redeploy |
| `Get-CopilotAtelierVersion` | Report installed version, deployed version, and currency |
| `Test-CopilotAtelier` | Read-only deployment, hash, link, hook, and settings diagnostics |
| `Uninstall-CopilotAtelier` | Remove unchanged owned files; preserve personal content and configuration |

Never hand-edit `ModuleVersion` in `source/CopilotAtelier.psd1`; GitVersion
supplies it at build time.

## Deployment boundary

`Install-CopilotAtelier` deploys only these directories to the Canonical
target:

- `agents/`
- `instructions/`
- `skills/`
- `prompts/`
- `hooks/`

The repository-local `.memory-bank/`, `tests/`, `Reference/`, the build system,
`plugin.json`, and documentation are not copied. `Keybindings/keybindings.json`
is merged into the VS Code user profile. `.copilotatelier.json` records the
version and schema-1 Owned-file paths with SHA-256. During apply it also records
pending operations and verified staging state; completed records remain schema
1. Matching untracked files remain unowned; legacy records cannot authorize
removal. Explicit Repair affects recorded files only. Install and Update accept
TargetPath and reject ambiguous account selection without prompting. Local
install/removal callers on one target coordinate with an exclusive handle.

## Discovery model

The Canonical target is `~/OneDrive/CopilotAtelier/` when OneDrive is available
and `~/CopilotAtelier/` otherwise. Discovery links expose its five deployed
directories through `~/.copilot/{agents,instructions,skills,prompts,hooks}`.

- Windows uses NTFS junctions.
- macOS and Linux use symbolic links.
- Agents, Instructions, and Skills need no `chat.*FilesLocations` entry.
- Prompts additionally use `chat.promptFilesLocations = ~/.copilot/prompts`.
- Hooks additionally use `chat.hookFilesLocations = ~/.copilot/hooks`.
- `-IncludeClaudeCodeLinks` adds `~/.claude/skills` and `~/.agents/skills`. It
  is off by default because VS Code reads all three user-level skill locations
  and would register every Skill more than once.
- Setup removes historical `~/CopilotAtelier/*` and
  `~/OneDrive/CopilotAtelier/*` entries while preserving unrelated user paths.

## VS Code settings

| Setting | Value | Purpose |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Apply Instructions by `applyTo` |
| `chat.includeReferencedInstructions` | `true` | Resolve referenced Instruction content |
| `chat.hookFilesLocations` | `~/.copilot/hooks` | Load the shared lifecycle hooks |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable reasoning tools |
| `github.copilot.chat.search.semanticTextResults` | `true` | Improve semantic search |
| `github.copilot.chat.skillTool.enabled` | `true` | Allow `context: fork` Skills |
| `github.copilot.chat.agent.maxRequests` | `500` | Support long agent workflows |
| `gitlens.ai.vscode.model` | `copilot:claude-opus-5` | GitLens model |

Setup removes the `github.copilot.advanced.model` key written by earlier
releases. `github.copilot.advanced` is the completions bag and has no documented
`model` member, so the value was never consumed.

Custom agents declare `model` as a priority array. The last entry must be a GA
model so a retirement degrades instead of breaking every agent.

## Execution constraints

Use the shared execution-safety Instruction: synchronous one-shot commands,
detached Pester/build runs, temporary logs, and no foreground polling. Never
mutate a remote without an explicit current-turn request.

## Validation

- `./build.ps1 -Tasks build, test` is the full gate. Add `-ResolveDependency`
  on the first run.
- Validate CI-affecting changes against a clean checkout, not just the
  developer worktree: clone the repository into a temporary directory, copy
  `output/` in as the build artifact, and run `./build.ps1 -Tasks test`. A
  worktree carries gitignored files such as `.memory-bank/promptHistory.md`
  that CI never has.
- Windows PowerShell 5.1 decodes a BOM-less UTF-8 file with the ANSI code page.
  A test that string-matches repository Markdown must read it with
  `-Encoding UTF8`, or every non-ASCII character becomes mojibake. Most reads
  in `tests/` still omit it and are only safe because they match ASCII.
- An environment-bound test declares its requirement through a
  `BeforeDiscovery` probe feeding `-Skip`, never through `#requires`.
  `#requires` fails Pester discovery on an unsupported host, which fails the
  whole run instead of skipping one file. Tag it `Unit` only if it really is
  portable, because the Linux job selects by tag.
- A hook resolves a payload-supplied path through .NET, never the PowerShell
  provider. The provider writes to standard error for a path it cannot resolve,
  and a hook's caller merges the streams, so that noise corrupts the JSON the
  hook writes to standard output.
- `tests/Workflows.Tests.ps1` parses every GitHub Actions workflow and rejects
  an expression in a step's `shell` key. That key accepts no context, so an
  expression there fails the whole workflow file at compile time; a
  matrix-driven shell belongs in `jobs.<job_id>.defaults.run`.
- Read `tests/` for what each suite covers; do not restate that inventory here.
  Three gates there constrain unrelated work and are easy to trip:
  `MemoryBankRouting.Tests.ps1` requires at least 50 percent average context
  reduction, so an append to a highly routed core file can fail it;
  `MemoryBankHealth.Tests.ps1` enforces the per-file line budgets; and
  `SkillFrontmatter.Tests.ps1` enforces a non-growing over-budget body baseline.
- PowerShell changes require AST parsing, focused Pester, and PSScriptAnalyzer
  where available.
- Pester is pinned to 5.7.1. `Initialize_TestResultSerialization` serializes
  file, drive, and provider references as paths or labels, then restores the
  caller's type data through build-exit cleanup, including failures. Raw
  provider metadata can stall `Export-Clixml` on both Windows hosts.
- Markdown Customizations require frontmatter checks and clean editor or
  markdownlint diagnostics.

## Sources of truth

Do not duplicate changing inventories here. Use:

- `Agents/` for Custom agents and tool declarations.
- `Instructions/` for auto-applied rules and `applyTo` patterns.
- `Skills/` for available Skills and their trigger descriptions.
- `Prompts/` for Prompt bindings.
- `Hooks/` for lifecycle events, hook commands, and the enforcement scripts.
- `source/CopilotAtelier.psd1` for the exported command surface.
- `build.yaml` for the build workflow, Pester configuration, and payload list.
- `plugin.json` for the agent plugin manifest.
- `README.md` for the user-facing catalog.
- `CHANGELOG.md` and git history for historical detail.

## Development setup

1. Clone the repository.
2. Run `Setup-CopilotSettings.ps1` to deploy the working tree, or
   `./build.ps1 -ResolveDependency -Tasks build, test` to build and validate.
3. Restart VS Code or reselect the Custom agent.
4. Verify Customization discovery in Copilot Chat diagnostics.
