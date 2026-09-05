<!-- markdownlint-disable MD033 MD041 -->
<!-- Logo floated left; two transparent variants switch by theme via <picture>.
     Judge on github.com — some in-editor previews mis-resolve prefers-color-scheme. -->
<picture>
  <source media="(prefers-color-scheme: dark)"
          srcset="assets/CA-logo-on-dark.png">
  <img align="left" width="300" alt="Copilot Atelier logo"
       src="assets/CA-logo-on-light.png">
</picture>
<!-- markdownlint-enable MD033 -->

**Portable GitHub Copilot customization** — agents, instructions, skills,
prompts, and hooks — synced across machines via OneDrive and linked into the
well-known `~/.copilot/` folders that VS Code and the Copilot CLI both read.

<!-- markdownlint-disable MD033 -->
<br clear="left">
<!-- markdownlint-enable MD033 -->

## Contents

- [Quick Start](#quick-start)
- [Purpose](#purpose)
- [Folder Structure](#folder-structure)
- [What Each Folder Contains](#what-each-folder-contains)
- [How Much Process You Want](#how-much-process-you-want)
- [Available Skills](#available-skills)
- [Migrating Legacy Memory Bank Records](#migrating-legacy-memory-bank-records)
- [VS Code Settings Applied](#vs-code-settings-applied)
  - [File Locations](#file-locations)
  - [Feature Flags](#feature-flags)
  - [AI Model Preferences](#ai-model-preferences)
- [Keybindings Applied](#keybindings-applied)
- [Setup on a New Machine](#setup-on-a-new-machine)
  - [1. PowerShell Gallery (recommended)](#1-powershell-gallery-recommended)
  - [2. Repository clone](#2-repository-clone)
  - [What either path does](#what-either-path-does)
  - [3. Agent plugin](#3-agent-plugin)
- [Building from Source](#building-from-source)
- [Verifying It Works](#verifying-it-works)
- [Deployment diagnostics and removal](#deployment-diagnostics-and-removal)
- [Client verification boundaries](#client-verification-boundaries)
- [Troubleshooting Skills](#troubleshooting-skills)
  - [YAML Frontmatter Is Required](#yaml-frontmatter-is-required)
  - [Blank Line After Frontmatter](#blank-line-after-frontmatter)
  - [Reload Required](#reload-required)
  - [Verifying Skills Are Loaded](#verifying-skills-are-loaded)
- [Useful Chat Shortcuts](#useful-chat-shortcuts)
- [Reference](#reference)
- [Featured In](#featured-in)
- [License](#license)

## Quick Start

You need PowerShell 5.1 or later, VS Code, and the GitHub Copilot Chat extension. No elevation is required.

```powershell
Install-Module -Name CopilotAtelier -Scope CurrentUser
Install-CopilotAtelier -InformationAction Continue
```

Restart VS Code. That is the whole setup — the agents appear in the Chat agent dropdown, skills and prompts appear under `/`, and instructions apply automatically to files matching their `applyTo` glob.

Keep it current with one command:

```powershell
Update-CopilotAtelier -InformationAction Continue
```

> [!NOTE]
> Two other paths exist: a [repository clone](#2-repository-clone) for working on the library itself, and an [agent plugin](#3-agent-plugin) that installs straight from the Git URL. The bundled hooks still require a PowerShell runtime.

Full detail: [Setup on a New Machine](#setup-on-a-new-machine) · [Verifying It Works](#verifying-it-works) · [Building from Source](#building-from-source).

## Purpose

VS Code discovers Customizations from well-known user locations. By default,
those files stay local to a single machine. Other Copilot clients share some
Discovery locations, but not every file type or runtime capability.

CopilotAtelier stores the canonical files in one folder named after the module,
preferring OneDrive for cross-machine sync, and links `~/.copilot/*` to that
target. The shared files stay consistent; each client still needs the
capabilities its selected Customizations require.

No `chat.*FilesLocations` settings are written for agents, instructions, or
skills. Prompts are VS Code-specific: installation registers
`~/.copilot/prompts` in `chat.promptFilesLocations`. The Copilot CLI does not
run VS Code Prompt files. Installation removes obsolete location entries for
this library while preserving unrelated user locations.

Each deployment populates one Canonical target. Older local trees are reported
and preserved because a directory name alone cannot establish ownership.

## Folder Structure

Two layouts are in play, and they are deliberately different shapes.

What gets **deployed** to your machine — unchanged by the plugin migration:

```text
~/OneDrive/CopilotAtelier/       # Used when OneDrive is detected (preferred)
~/CopilotAtelier/                # Fallback — used only when OneDrive is not installed
├── agents/          # Custom agents (.agent.md files)
├── instructions/    # Custom instructions (.instructions.md files)
├── skills/          # Agent skills (folders with SKILL.md)
├── prompts/         # Prompt files / slash commands (.prompt.md files)
└── hooks/           # Lifecycle hooks (hook config JSON plus scripts)
```

How the **repository** stores them, which is also the installable plugin package ([Agent Plugins 1.0](https://agent-plugins.org/)):

```text
plugin.json                     # Declares the Agent Plugins 1.0 schema
skills/                         # Portable component — read by any conformant client
com.github.copilot/             # Copilot client-extension namespace
├── agents/                      # *.agent.md
├── rules/                       # *.instructions.md
├── commands/                    # *.prompt.md
└── hooks/hooks.json             # plus scripts/
keybindings/                    # Not a plugin component type; merged into VS Code
```

`Install-CopilotAtelier` maps between them — `com.github.copilot/rules` deploys as `instructions`, `com.github.copilot/commands` as `prompts` — so the discovery links at `~/.copilot/*` are exactly what they always were.

The folder name of the canonical target is `CopilotAtelier`, matching the module name. Repository-only content such as `.memory-bank/`, `tests/`, `reference/`, the build system, and documentation is not copied into the Canonical target. `keybindings/keybindings.json` is merged into the VS Code user profile rather than copied there.

## What Each Folder Contains

| Folder | File Type | Purpose |
|---|---|---|
| **Agents** | `*.agent.md` | Custom AI personas with specific tools, instructions, and model preferences. Core agents cover the software development pipeline; supplementary agents serve domain-specific side use cases. Appear in the agents dropdown in Chat. |
| **Instructions** | `*.instructions.md` | Coding standards, conventions, and guidelines. Can auto-apply based on file glob patterns (`applyTo`) or be attached manually. Includes [`copilot-authoring.instructions.md`](com.github.copilot/rules/copilot-authoring.instructions.md), which governs how the files in this repo are authored. |
| **Skills** | `<name>/SKILL.md` | Specialized capabilities with scripts, examples, and resources. Loaded on-demand when relevant. Appear as `/slash` commands. |
| **Prompts** | `*.prompt.md` | Reusable task templates invoked as `/slash` commands. Best for single, repeatable tasks like scaffolding or code review. |
| **Hooks** | `*.json` + `scripts/` | Shell commands run at fixed points in the agent loop. Deterministic guardrails that do not depend on the model choosing to obey them. See [`com.github.copilot/hooks/README.md`](com.github.copilot/hooks/README.md). |
| **Keybindings** | `keybindings.json` | Shared VS Code keybindings merged idempotently into `%APPDATA%\Code\User\keybindings.json`. See [Keybindings Applied](#keybindings-applied). |

## How Much Process You Want

The four core agents work alone by default and can also chain into one workflow.
Nothing has to be configured — the setting is whatever you type.

| You want | Type this |
|---|---|
| One agent only *(default)* | nothing |
| One agent, plus a security review | `review: on` |
| The agent to judge whether a review is needed | `review: auto` |
| The full cycle: architect → engineer → reviewer → writer | `cycle: full` |
| To stop a running cycle | `cycle: off` |

A cycle progresses on its own once you ask for it, and only its last stage writes
the changelog entry and the commit. Full detail, the trigger phrases it accepts,
and the ones it deliberately ignores are in
[`com.github.copilot/agents/README.md`](com.github.copilot/agents/README.md#choosing-how-much-process-you-want).

### Completing a specification-driven repository

Run `/complete-specifications` to inventory atomic requirements, exit criteria,
open Decisions, local gaps, and an optional local issue snapshot. The Prompt
starts a restricted controller, which assigns one isolated implementer per work
item and one independent reviewer per result.

The workflow reports implementation, local-test, live-verification, and total
specification closure separately. Live validation is off by default. Enabling
it requires a directly supplied containment-profile SHA-256 and a pinned live
profile; a separate data-isolated runner owns any endpoint access. Shared and
production mutations become supervised procedures and remain visibly
incomplete. Nothing is pushed.

## Available Skills

| Skill | Description |
|---|---|
| **automatedlab-deployment** | Build and deploy Hyper-V lab environments using AutomatedLab. Covers installation, lab definitions, roles (AD, File Server, Routing, PKI, SQL, etc.), networking, and post-deployment configuration. |
| **automatedlab-proxmox** | Diagnose AutomatedLab Windows provisioning and remoting failures on Proxmox/QEMU using orchestrator, hypervisor, guest-agent, Windows setup, and protocol evidence. Covers QEMU command completion, Sysprep/AppX failures, post-restart WinRM ordering, metadata flags, stale modules, and live verification. |
| **datum-configuration** | Comprehensive reference for the Datum PowerShell DSC configuration data module. Covers hierarchical data composition, `Datum.yml` configuration, resolution precedence, merge strategies, knockout prefix, handlers, RSOP computation, and the DscWorkshop reference implementation. Includes ProjectDagger-specific patterns, CommonTasks composite resources, DscConfig.Demo, build pipeline flow, GPO to DSC migration, and ecosystem relationships. |
| **dsc-troubleshooting** | Debug and troubleshoot PowerShell DSC resource failures on target nodes. Covers LCM diagnostics, event log analysis, resource debugging with `Wait-Debugger` and `Enter-PSHostProcess`, cache clearing, common exit codes, installer log analysis, and Windows Server 2025 specific issues (Start-Process UNC path hangs, class-based resource ForceModuleImport failures, SYSTEM profile logs). |
| **elster-form-capture** | Drive the Mein ELSTER web form by machine to capture a German tax return, while the taxpayer authenticates and transmits personally — `§ 150 Abs. 2 S. 1 AO` makes transmission non-delegable. Built on the one fact that decides everything: the official ERiC field numbers behind `name="fields[…]"` are stable across assessment years, the `Teilseite` and `Zeile` numbers are not. Covers sub-page navigation, repeat rows and sub-forms, mandatory-field traps, eData gaps, the "Daten vorhanden" completeness test, 29 recorded gotchas, and a machine comparison of every target amount against the summary page. Ships a harvested Feldkarte for `Anlage V`, `V-Sonstige`, `N`, and `Vorsorgeaufwand`. |
| **german-legal-research** | Legal research and statement drafting for German law (Deutsches Recht). Specializes in tenancy/rental law (Mietrecht), property management, and operating cost disputes. |
| **german-tax-research** | German income tax (Einkommensteuer) case work: assessment-notice review, deadline computation under the four-day notification fiction, point-by-point answers to a `Belegaufforderung`, reconciliation of every claimed figure against the return actually transmitted, and formal German drafts for `Einspruch`, `Begründung`, `AdV`, `Ruhen`, and `§ 153 AO` corrections. References cover AO procedure, V+V and AfA including `§ 7i`, Werbungskosten and Sonderausgaben, year-keyed amounts and filing deadlines, and letter templates; ships `Get-SteuerFrist.ps1` for the notification and objection dates including state holidays. |
| **grammar-check** | Identify grammar, logical, and flow errors in text and suggest targeted fixes. Analyzes spelling, punctuation, subject-verb agreement, tense consistency, and transitions. |
| **memory-bank** | Initialize, route, check, and safely migrate a repository Memory Bank for durable work. Manages seven required version-controlled files plus local prompt history, preserves existing content byte-for-byte, supports namespaced career, legal, and tax records, checks provenance and compactness budgets, retains a Full-read fallback, and provides offline pass@k/pass^k evaluation of natural-language route selection. |
| **citation-integrity** | Verify every external claim, quote, statistic, and reference in generated text against a fetched source. Defines a six-class failure taxonomy (F1 fabricated reference → F6 anchorless claim), a three-layer anchor (locator + ≤25-word quote + stable identifier), a `VERIFIED` / `MISMATCH` / `NOT_FOUND` verdict scheme with no gray zone, and a cross-index triangulation rule for contamination signals. |
| **devils-advocate-review** | Argue against a proposal, design, claim, or draft from a hostile-but-fair position with explicit safeguards against sycophancy. 1–5 rebuttal scoring rubric (concession only at ≥ 4, no consecutive concessions, attack-intensity preservation), named deflection classes (reframe, authority, volume, sentiment, goalpost shift, tu quoque, premature consensus), frame-lock self-check every three rounds, closing report with sycophancy log. |
| **social-signal-sweep** | Recency-bounded sweep (default 30 days) of what people are publicly saying about a topic across GitHub, Hacker News, Reddit, and Stack Overflow, plus a browser-only tier for YouTube and X. Produces a tier-8 lead sheet (platform, date, engagement signal, link, what-to-verify) to seed a deeper investigation — strictly leads-only, never citable. No bundled engine, no API keys, no cookies; uses web fetch, the GitHub tools, and the simple browser. Feeds the `research-analyst` SOURCE phase. |
| **outlook-calendar-export** | Export Outlook calendar entries to Markdown files via COM automation in PowerShell. Covers recurring appointments (`IncludeRecurrences`), date range filtering, Markdown generation with metadata tables, index file creation, and UTF-8 encoding best practices. |
| **outlook-email-export** | Export and extract emails from Outlook via COM automation in PowerShell. Covers searching by sender, recipient, CC, subject, or date range across multiple folders. |
| **pester-patterns** | Common Pester 5 test patterns and recipes for PowerShell module testing. Covers mocking file systems, REST APIs, DSC resources, databases, and credentials, plus Pattern 14 on Pester 5 runspace isolation — helpers used inside `It` must live in `BeforeAll` (symptom: misleading `CommandNotFoundException`); `-ForEach` data must go in `BeforeDiscovery`, not `BeforeAll`. |
| **sampler-build-debug** | Debug and troubleshoot Sampler-based PowerShell module builds and Pester 5 test failures. Covers running builds safely, reading Pester results, and diagnosing common failures. |
| **test-driven-development** | Test-first workflow for PowerShell/DSC: the red-green-refactor loop, writing a failing Pester test before the code, the test pyramid, DAMP-over-DRY readability, choosing what and at which level to test, and treating bug fixes as test-first. Enforces "no production change without a covering test". |
| **debugging-and-error-recovery** | A disciplined general debugging workflow — reproduce, localize, reduce, fix the root cause, then guard with a regression test. Stop-the-line on a red build; fix causes not symptoms; never swallow an error to hide a failure. Instruments every boundary in a layered system before hypothesising, and treats a third failed fix as a design signal rather than a cue for a fourth attempt. PowerShell tactics for the call stack, tracing, and error records. |
| **code-review-and-quality** | A reusable five-axis code-review workflow (design, correctness, complexity, tests, clarity) for PowerShell/DSC changes. Severity labels (Blocker/Major/Minor/Nit), change sizing to stay reviewable, must-fix vs opinion, review speed and tone, and an author self-review gate. |
| **subagent-dispatch** | Protocol for delegating work to subagents: naming the model per task tier, writing a dispatch that carries the task instead of the session history, handing artifacts over as files, never pre-judging a reviewer and never handing a re-performer the expected values, keeping a ledger that survives context compaction, verifying a subagent's claim against the diff, and capping the fix loop before it becomes churn. |
| **sampler-framework** | Comprehensive reference for the Sampler PowerShell module build framework. Covers project structure, `build.yaml` configuration, dependency management, build workflows, and testing patterns. |
| **mecm-dsc-deployment** | Deploy and troubleshoot Microsoft Endpoint Configuration Manager (MECM/SCCM) via DSC using ConfigMgrCBDsc, CommonTasks, and UpdateServicesDsc modules in DscWorkshop/Datum environments. Covers ADK/WinPE product registration, SCCM 2509 silent install, UpdateServicesDsc bugs, Datum merge strategies for Tiny scenarios, cross-domain SQL access, and AutomatedLab operational patterns. |
| **pandoc-docx-export** | Export Markdown documents to polished DOCX files using pandoc with custom formatting: landscape pages for wide tables, custom column widths, reduced table font sizes, and proper `reference.docx` styling. |
| **pdf-to-markdown** | Convert PDF files to well-structured Markdown using .NET-native PDF parsing in PowerShell — no external tools required. Decompresses zlib/deflate content streams, decodes hex-encoded text operators, and reconstructs lines by Y-coordinate positioning. Best suited for structured documents like payslips, invoices, and reports. |
| **sampler-migration** | Step-by-step guide for migrating a legacy PowerShell module project to the Sampler build framework. Covers migrating from AppVeyor, PSDepend, PSDeploy, and Pester 4. |
| **send-outlook-email** | Send emails via the Outlook COM API from PowerShell. Supports plain-text and HTML-formatted emails with subject and body content. |
| **create-outlook-draft** | Create Outlook email drafts from Markdown email files via COM automation in PowerShell. Parses metadata tables (To, CC, Subject), converts Markdown body to styled HTML (tables, bold, lists), and saves drafts to the Outlook Drafts folder. Handles COM lifecycle, locked items, duplicate cleanup, and batch processing. |
| **docx-to-markdown** | Convert DOCX (Word) files to Markdown using .NET-native ZIP/XML parsing in PowerShell — no pandoc, Word COM, or Python required. Extracts paragraph text with heading styles and handles both English and German style names. Fallback when pandoc is unavailable. |
| **xlsx-to-markdown** | Convert XLSX (Excel) files to Markdown tables using .NET-native ZIP/XML parsing in PowerShell — no Excel COM, ImportExcel, or Python required. Handles shared strings, cell references, multi-sheet workbooks, inline strings, and column letter-to-index conversion. |
| **microsoft-todo-tasks** | Create, list, and manage Microsoft To Do tasks via the Graph REST API using raw OAuth2 device code flow in PowerShell. Bypasses the buggy Microsoft.Graph SDK (WAM broker issues, System.Text.Json conflicts) and supports personal Microsoft accounts (live.com). |
| **long-running-job-monitor** | Monitor long-running test suites, builds, deployments, and remote jobs — including a run the agent starts itself — with timestamped logs, terminal markers, structured `Summary` / `Liveness` / `ProgressToken` probes, phase-sized stall thresholds, channel-loss recovery, and restart-scoped readiness. |
| **winrm-troubleshooting** | Diagnose WinRM connectivity and post-restart readiness failures. Covers guarded service recovery, listener and certificate configuration, scoped firewall and TrustedHosts changes, authentication, raise-only quotas, event diagnostics, and PowerShell Direct fallback. |
| **marp-slide-overflow** | Detect and fix content overflow in Marp slide decks before exporting to PPTX/PDF/PNG. Provides a Puppeteer-based `scrollHeight`-vs-viewBox detector, a side-by-side HTML review report, a two-tier CSS density pattern (`dense` / `compact`), a `fillRatio` decision table, a mandatory PNG-based visual verification workflow (Recipe 0), a `mermaid-cli` pre-render pattern (Marp has no native mermaid support; client-side mermaid.js fails in PDF/PPTX) with content-hash caching, image-height CSS cap, and mermaid label-quoting gotchas, and Recipe 5 on speaker-note coverage — code-fence-aware slide splitting, directive vs. real-note filtering, section-divider assertions, a drop-in Pester guard, and a `notes-title-map.psd1` pattern for multi-file decks. |
| **whisper-pyannote-transcription** | Transcribe long audio/video on Windows with GPU acceleration using `faster-whisper` (CTranslate2, large-v3) and add speaker labels with `pyannote.audio` 3.1. Covers ffmpeg 16 kHz mono extraction, Python 3.12 venv isolation, CUDA-matched PyTorch wheels (`cu128`), Hugging Face gated-model access, and merging RTTM speaker turns into Whisper segments to produce speaker-labeled SRT, JSON, and grouped transcript text. Documents the Windows `torchcodec` bypass (preload waveform via `torchaudio`) and the `Tee-Object` exit-code trap. |
| **authenticated-web-extraction** | Extract data from sites that require login (LinkedIn, GitHub, Sessionize, Microsoft 365, X, Meetup) using a persistent Playwright + Microsoft Edge profile at `%LOCALAPPDATA%\CareerAuthBrowser\`. Ships a bundled `bootstrap/` (package.json, `open.mjs`, `extract.mjs`, `check-logins`, `dump-cookies`) for one-command profile rebuild. Documents the session-cookie-vanish workaround (re-inject saved cookies on every run), per-site auth-cookie names (`li_at`, `user_session`, `.AspNet.ApplicationCookie`, `auth_token`, `MEETUP_MEMBER`), Edge tracking-prevention flags required for OAuth callbacks, and the profile-lock orphan-process gotcha. |
| **windows-gui-screenshot-capture** | Capture Windows desktop GUI screenshots and assemble screenshot-embedded Markdown user manuals. Branches between self-capturing scene modes for modifiable apps and external drivers for existing or third-party executables. Covers rendering-engine-specific APIs, process-scoped control discovery, event-based dialog/control readiness, GPU and premature black frames, cross-process controls, native dialogs, state restoration, pixel/landmark validation, and final visual review. Ships per-engine and external-Win32 references plus a native-dialog helper. |
| **brand-logo-system** | Design a project's visual identity and render it as SVG masters plus deterministic PNG deliverables, export the eleven-slot set a shared logo library expects, and wire the chosen variants into the project itself. Covers recovering a palette and mark from a project's existing artwork by pixel count, composing primary lockups, glyph-only marks, app icons, splash screens and monochrome variants from one brand definition, headless-Edge rasterisation at exact canvas sizes, a measured gate over count, naming, slot parity, dimensions, corner alpha, painted bounds, centring, and ink coverage at 32 and 16 px, and the integration step: naming the target repository before writing to it, the floated README header GitHub's sanitiser allows, the direct-image-URL rule for a package icon, and the social preview. Ships a definition-driven renderer. |
| **agent-evals** | Measure whether a Customization works instead of trusting one lucky run. Covers the three stacked questions — is it discovered (trigger-rate evals), does it hold up across runs (capability and regression sets, pass@k vs pass^k, deterministic / LLM-as-judge / human graders), and does it beat no skill at all (with/without delta on pass rate, tokens, duration). Starts from native VS Code tooling and Waza and falls back to the bundled `run-evals.ps1` and `run-trigger-evals.ps1` harnesses, whose `Prepare` and `Grade` modes need no model backend. |
| **agent-security-review** | Review AI agents, LLM-backed features, MCP servers, and prompt/skill/agent definitions for agentic-security risk. Ships the lethal-trifecta test (private data × untrusted content × outbound channel), OWASP Top 10 for LLM Applications (2025) quick checks, a containment-first checklist, and MCP / tool-permission review. Breaks the trifecta rather than filtering it, and treats every tool return value as untrusted. |
| **skill-creator** | Author, audit, and improve `skills/**/SKILL.md` files against the [Agent Skills open standard](https://agentskills.io/): progressive disclosure (body ≤ 500 lines, references one level deep), the six-step authoring frame, category-level descriptions with train/validation trigger evals, the 1024-character description cap, and cross-skill overlap audits. Also decides whether something deserves a Skill at all, and whether it is one Skill, two, or a reference. |
| **mcp-builder** | Design, scaffold, and ship Model Context Protocol (MCP) servers that expose an API or local capability as well-named tools an LLM can call. Four-phase workflow (research → implement → review → evaluate), TypeScript vs Python SDK choice, stdio vs streamable-HTTP transport, tool naming and description discipline, Zod / Pydantic schemas, pagination, actionable error messages, MCP Inspector testing, and a 10-question realistic-task eval rubric. Includes the Windows / VS Code Copilot stdio gotchas. |
| **grill-me** | Adversarial requirements interview that asks 40–100 questions across purpose, users, inputs and outputs, failure modes, edge cases, security, performance, ownership, rollback, observability, non-goals, and open questions — before any code, design, or diagram is written. The transcript and the Design Concept it produces are the deliverable; everything downstream waits for explicit sign-off. |
| **gilb-requirements-engineering** | Quantified requirements engineering with Tom and Kai Gilb's method: give every quality a Planguage `Scale` and `Meter` with benchmarks and numeric targets, rank design ideas in an Impact Estimation Table, plan delivery as measurable Evo steps, and inspect specifications with Specification Quality Control. The one rule: no quality requirement without a Scale, a Meter, and at least one number. |
| **doc-coauthoring** | Three-stage workflow for co-authoring a substantive document with a user: Context Gathering (meta-questions, info dump, clarifying questions), section-by-section Refinement (clarify → brainstorm → curate → draft → surgical edits), and Reader Testing, where a fresh assistant or subagent reads the document cold and answers predicted reader questions to surface blind spots. |
| **pswritehtml-reporting** | Generate interactive HTML reports, dashboards, tables, charts, and network diagrams from PowerShell objects with the PSWriteHTML module — no hand-written HTML, CSS, or JavaScript. Covers `New-HTML`, `New-HTMLTable` (DataTables filtering, paging, conditional formatting), `New-HTMLChart`, Section/Panel/Tab layout, `New-HTMLDiagram`, `Out-HtmlView`, large-dataset tuning, and HTML email bodies. |
| **evidence-package-assembly** | Assemble paginated evidence packages (`Anlagen`) for authorities, courts, and insurers on Windows: verify documents against the claims made about them, decide which sheets may be omitted, render a Markdown cover with a locator index to PDF via pandoc and headless Edge, merge with pypdf, and verify page ranges, text layer, and the sources' own page numbering. |
| **copilot-usage-stats** | Report how many tokens, API calls, and how much time a project has consumed, broken down by model, session, day, or surface, and convert those tokens into GitHub AI Credits and dollars at the published per-model rates. Carries the repository-scoped join that survives the three unnormalized spellings of the same repository, the verified fact that `input_tokens` already contains `cache_read_tokens`, the `cost` column that holds a legacy request multiplier rather than money, and the reason no hook, transcript, or local database can answer the question. Paired with the `/usage` Prompt on `Ctrl+K U`. |

## Migrating Legacy Memory Bank Records

Career, legal, and tax records now live under `.memory-bank/career/`,
`.memory-bank/legal/`, and `.memory-bank/tax/`. Older repositories may still
have files such as `profile.md`, `case-*.md`, or `deadlines.md` directly under
`.memory-bank/`. Installation and updates never scan or change those private
repository records.

Run the migration from the repository you intend to update. Planning is
read-only by default and inventories only that repository's direct
`.memory-bank/` children:

```powershell
$skillRoot = "$HOME/.copilot/skills/memory-bank"
$planner = "$skillRoot/scripts/New-MemoryBankRoleMigrationPlan.ps1"
$plan = & $planner -Path $PWD.Path
$plan.Entries | Format-Table Name, Classification, Decision, Status
```

Unambiguous files are assigned automatically. Ambiguous files such as
`deadlines.md` require an explicit role, `ManualSplit`, or `Skip` decision.
Save the metadata-only plan, preview the complete apply, and then run it only
after reviewing the result:

```powershell
$plan = & $planner -Path $PWD.Path -Assignment @{
  'deadlines.md' = 'tax'
  'session-log.md' = 'ManualSplit'
} -SavePlan

$applicator = "$skillRoot/scripts/Invoke-MemoryBankRoleMigration.ps1"
& $applicator -Path $PWD.Path -PlanPath $plan.PlanPath -WhatIf
& $applicator -Path $PWD.Path -PlanPath $plan.PlanPath -Confirm
```

Apply validates the whole plan before writing, rejects changed sources,
conflicts, path escapes, and reparse points, and copies bytes without replacing
destinations. It verifies SHA-256 after every copy and never moves or deletes a
legacy source. Reapplying the same plan is safe; identical destinations report
`AlreadyMigrated`. Unknown, skipped, and manual-split files remain untouched.

## VS Code Settings Applied

`Install-CopilotAtelier` configures the following in `settings.json`:

### File Locations

Discovery links expose agents, instructions, and skills without additional
location settings. Installation removes historical `~/CopilotAtelier/*` and
`~/OneDrive/CopilotAtelier/*` entries while preserving unrelated user locations.
VS Code Prompts need the explicit `chat.promptFilesLocations` entry for
`~/.copilot/prompts`; they are not a Copilot CLI workflow. The five directories
share one Canonical target:

```text
%USERPROFILE%\.copilot\agents       --> <target>\Agents
%USERPROFILE%\.copilot\instructions --> <target>\Instructions
%USERPROFILE%\.copilot\skills       --> <target>\Skills
%USERPROFILE%\.copilot\prompts      --> <target>\Prompts
%USERPROFILE%\.copilot\hooks        --> <target>\Hooks
```

Where `<target>` is `%USERPROFILE%\OneDrive\CopilotAtelier` when OneDrive is installed, otherwise `%USERPROFILE%\CopilotAtelier`.

If one of the `~/.copilot\<name>` folders already exists as a real directory:

- Empty → removed silently and replaced with the junction.
- Non-empty → the script prompts before deleting. On `y`, its contents are merged into the target (existing target files are not overwritten) and then the directory is removed and replaced with the junction. On `n`, the junction is skipped and a warning is printed.

Existing junctions are recreated on every run so they always point at the current target.

#### Claude Code and Agent Skills clients (opt-in)

Run `Setup-CopilotSettings.ps1 -IncludeClaudeCodeLinks` to additionally link `~/.claude/skills` and `~/.agents/skills` to the same `skills` directory, so Claude Code and other [agentskills.io](https://agentskills.io/) clients discover the library too. This is off by default: VS Code reads all three user-level skill locations, so enabling it registers every Skill more than once in VS Code. Use it on machines where a non-Copilot client is the primary consumer. These two links are create-only — if a path already exists it belongs to that other tool and is left untouched.

### Feature Flags

| Setting | Value | What It Does |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Auto-apply `.instructions.md` files when their `applyTo` glob matches files being worked on |
| `chat.includeReferencedInstructions` | `true` | Follow Markdown links in instruction files and load referenced content into context |
| `chat.hookFilesLocations` | `~/.copilot/hooks` | Load the shared lifecycle hooks; merged so user-added hook locations and the Claude Code defaults survive |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable the thinking tool so agents can reason through complex problems before acting |
| `github.copilot.chat.search.semanticTextResults` | `true` | Improve search results in agent mode with semantic matching |
| `github.copilot.chat.skillTool.enabled` | `true` | Allow Skills that declare `context: fork` to run in a dedicated subagent and return only their result |
| `github.copilot.chat.agent.maxRequests` | `500` | Raise the per-turn agent request budget so long autonomous loops do not stall on the default limit |

### AI Model Preferences

Every agent in [`com.github.copilot/agents/`](com.github.copilot/agents/) declares `model` as a priority array — `['Claude Opus 5 (copilot)', 'Claude Opus 4.8 (copilot)']` — so a model retirement degrades to the GA fallback instead of breaking every agent at once.

| Setting | Value | What It Does |
|---|---|---|
| `gitlens.ai.vscode.model` | `copilot:claude-opus-5` | Use Claude Opus 5 for GitLens AI features (commit messages, explanations) |

> **Note on model availability**: Opus 5 requires Copilot Pro+, Business, or Enterprise. On other plans VS Code falls back to the next entry in the agent's `model` array, then to its default. Setup also removes the `github.copilot.advanced.model` key written by earlier releases: `github.copilot.advanced` is the completions bag and has no documented `model` member, so the value was never consumed.

## Keybindings Applied

The setup script merges the bindings in [`keybindings/keybindings.json`](keybindings/keybindings.json) into `%APPDATA%\Code\User\keybindings.json`. The merge is idempotent (match key: `key + command + when`), preserves user-added bindings, and creates a timestamped backup on every run.

| Key | Command | Purpose |
|---|---|---|
| `Ctrl+K X` | `PowerShell.RestartSession` | Restart the PowerShell integrated console |
| `Ctrl+K N` | `workbench.action.terminal.moveIntoNewWindow` | Pop the active terminal into a new window |
| `Ctrl+K K` | `workbench.action.chat.openInNewWindow` | Pop the Chat view into a new window |
| `Ctrl+K U` | `workbench.action.chat.open` | Run the `/usage` Prompt — this project's Copilot token and model usage |
| `Ctrl+Enter` | `workbench.action.chat.submit` | Submit chat prompt (replaces plain `Enter`) |
| `Enter` | `-workbench.action.chat.submit` | Disabled so plain `Enter` always inserts a newline in the chat input |

## Setup on a New Machine

There are three installation paths. The PowerShell Gallery is the recommended one because it carries every customization type and brings versioning and an update command with it.

### 1. PowerShell Gallery (recommended)

```powershell
Install-Module -Name CopilotAtelier -Scope CurrentUser
Install-CopilotAtelier -InformationAction Continue
```

The module ships `Agents`, `Instructions`, `Skills`, `Prompts`, `Hooks`, and `Keybindings` as part of its payload, so a Gallery install carries the same content as a repository clone.

| Command | Purpose |
|---|---|
| `Install-CopilotAtelier` | Deploys the customizations to the canonical target, links the `~/.copilot` discovery folders, and merges the VS Code settings and keybindings. |
| `Update-CopilotAtelier` | Checks the Gallery for a newer version, installs it, and redeploys. `-Force` redeploys the current version; `-SkipDeployment` stages the update for later. |
| `Get-CopilotAtelierVersion` | Reports the installed module version, the deployed version, and whether the deployment is current. |

Both `Install-CopilotAtelier` and `Update-CopilotAtelier` write their progress to the information stream, so add `-InformationAction Continue` when you want to watch each step.

Useful switches:

| Switch | Effect |
|---|---|
| `-IncludeClaudeCodeLinks` | Also links `~/.claude/skills` and `~/.agents/skills`. Off by default; see [Claude Code and Agent Skills clients](#claude-code-and-agent-skills-clients-opt-in). |
| `-SkipCopilotCliEnvironment` | Leaves `COPILOT_ALLOW_ALL` alone. Installation otherwise sets it to `1` at User scope, which is what stops the GitHub Copilot CLI prompting for every tool call. |
| `-WhatIf` | Reports what would change without touching anything. |

Run `Get-Help Install-CopilotAtelier -Full` for the complete parameter reference.

#### Staying up to date

```powershell
Update-CopilotAtelier -InformationAction Continue
```

`Update-CopilotAtelier` compares the installed version against the Gallery,
installs a newer one if available, and redeploys its owned files. User-added
files remain in place. A conflict with a locally changed file stops deployment;
`-Force` does not override that protection. Use `-Force` to redeploy the current
version and `-SkipDeployment` to stage an update you will deploy later.

`Get-CopilotAtelierVersion` answers "is what I have actually deployed?":

```text
Version         : 4.0.0
DeployedVersion : 4.0.0
DeployedOn      : 2026-08-26 10:12:44
TargetPath      : C:\Users\you\OneDrive\CopilotAtelier
IsCurrent       : True
```

`IsCurrent : False` means the module was updated but the customizations on disk still come from an older version — run `Install-CopilotAtelier` to catch them up. The values come from `<target>/.copilotatelier.json`, which every deployment rewrites.

#### More than one machine

When OneDrive is present the canonical target lives inside it, so a second machine that already syncs the folder still needs its own `Install-CopilotAtelier` run to create the `~/.copilot` links and patch VS Code. After that, editing an agent in the synced folder propagates on its own; a module update needs `Update-CopilotAtelier` on each machine.

### 2. Repository clone

1. Clone this repository (or sign into OneDrive if you already keep a synced clone there).
2. Open PowerShell and run the setup script from the cloned location, for example:

```powershell
# From a local clone
& "<path-to-clone>\Setup-CopilotSettings.ps1"

# Or from a OneDrive-synced clone outside the Canonical target
& "$env:USERPROFILE\OneDrive\CopilotAtelier-src\Setup-CopilotSettings.ps1"
```

[`Setup-CopilotSettings.ps1`](Setup-CopilotSettings.ps1) dot-sources the module commands from `source/` and runs `Install-CopilotAtelier` against the clone, so the working tree is deployed without building or installing the module first.

Keep the clone outside the Canonical target. Overlapping source and deployment
trees are rejected before writing, including during `-WhatIf`.

3. Restart VS Code.

### What either path does

The Customizations are copied into `~/OneDrive/CopilotAtelier/` when OneDrive
is detected, or into `~/CopilotAtelier/` otherwise. Discovery links expose the
five deployed directories. VS Code settings and keybindings are merged with
timestamped backups. The Deployment record at `<target>/.copilotatelier.json`
stores the version and each owned file's relative path and SHA-256.

Installation validates the complete file plan before writing, preserves
untracked files and legacy trees, and retires only unchanged owned files.
Source and destination hashes are rechecked during apply. A non-empty real
Discovery directory remains untouched unless `-Force` requests a lossless
merge; conflicting content is still preserved. Reparse points at or below the
selected payload and deployment roots are refused, not followed. Trusted parent
aliases remain supported. Do not run deployment and removal concurrently;
these checks are not a filesystem transaction or a sandbox.

### 3. Agent plugin

The repository is also an [Agent Plugins 1.0](https://agent-plugins.org/)
package, installable from its Git URL without manually cloning or installing
the PowerShell module. Hook execution still needs PowerShell:

1. Run **Chat: Install Plugin From Source** from the Command Palette.
2. Enter `https://github.com/raandree/CopilotAtelier`.

Plugin-provided skills appear as `/copilot-atelier:<skill>` and update automatically when VS Code checks for extension updates. You can enable or disable the whole library per workspace from the **Agent Plugins - Installed** view, which the `~/.copilot` link model cannot do — that one is all-or-nothing per machine.

[`plugin.json`](plugin.json) declares the canonical `$schema`, which is what selects the format. Skills are the portable component and are read by any conformant client from `skills/`. Custom agents, instructions (`rules`), prompt files (`commands`), and hooks are Copilot-specific and ship from the [`com.github.copilot/`](com.github.copilot/) namespace, which other clients ignore without rejecting the package.

> [!NOTE]
> Two caveats matter before you choose this path. Hooks bundled in a plugin
> execute on your machine, so review them first; see
> [`com.github.copilot/hooks/README.md`](com.github.copilot/hooks/README.md).
> Custom agent discovery is cross-client, but capabilities vary by client.
> These profiles are authored and tested primarily in VS Code. Another Copilot
> client can ignore unavailable product-specific tool identifiers, VS Code
> handoffs, or a model priority array it does not support. Treat installation as
> discovery compatibility, not proof of identical runtime behavior. Agent
> Skills are the portable behavior layer defined by Agent Plugins 1.0.

Keybindings are not a plugin component type. The module can supply them, but
it also deploys the Customizations: enabling both installation paths in the
same client can duplicate Discovery or hook execution. Choose one active path
per client and verify its loaded locations. The Deployment record describes
only the module or clone deployment, never the native plugin cache.

### Sensitive local-data research

Some domain Custom agents intentionally need both private local material and
external capabilities. Tax work may read receipts from OneDrive, career work
may assess community contributions, and both may run local PDF, spreadsheet,
or OCR tools before using public websites. Removing every web or execution tool
would make those agents unable to do their job. Treat access as a staged
workflow instead:

1. **Narrow local intake.** Grant read-only access only to the specific
  OneDrive or evidence folder needed for the task, for example through
  `chat.additionalReadAccessFolders`. Do not sweep the whole user profile when
  one folder is sufficient.
2. **Transform locally.** Run PDF extraction, spreadsheet parsing, and OCR on
  the local machine. Write derived files to a task-specific local staging
  folder and keep raw documents out of web queries and tool arguments.
3. **Minimize public research.** Search with the smallest non-identifying facts
  that answer the question. Do not send names, tax identifiers, addresses,
  document text, or private source files to public search, arbitrary MCP
  servers, or external analysis services.
4. **Separate authenticated actions.** Use an agent-opened ephemeral browser
  for public research. Use an authenticated tab only when the user explicitly
  shares it; the user signs in and confirms submissions, messages, uploads,
  payments, and other irreversible actions.
5. **Enforce high-risk boundaries outside the prompt.** Keep approvals
  session-scoped and use domain and command allow-lists. For stronger isolation,
  run terminal and untrusted-content work in WSL2, a dev container, or a VM
  with filesystem and network policy. Native Windows VS Code sessions do not
  currently provide the same OS-level terminal sandbox as macOS, Linux, and
  WSL2.

Tool availability is therefore not blanket authorization. The risk appears
when one model invocation can simultaneously read private data, consume
attacker-controlled content, and use an outbound channel. Staging the workflow
and enforcing boundaries between those phases preserves the useful
capabilities while reducing what a prompt-injected step can reach. See
[AI security in VS Code](https://code.visualstudio.com/docs/agents/run/security)
for the current approval, sensitive-file, workspace-trust, and sandbox controls.

## Building from Source

The repository is a [Sampler](https://github.com/gaelcolas/Sampler) project. The module sources live in `source/`, the customization directories stay at the repository root, and the `Copy_Customizations_To_Output` build task copies them into the built module.

```powershell
# First run; resolves the build dependencies into output/RequiredModules
./build.ps1 -ResolveDependency -Tasks build

# Subsequent runs
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```

The version comes from [GitVersion](https://gitversion.net/) via [`GitVersion.yml`](GitVersion.yml), so the built module lands in `output/module/CopilotAtelier/<version>/`. [`.github/workflows/ci.yml`](.github/workflows/ci.yml) packages once on `ubuntu-latest`, tests that artifact on Linux, macOS, Windows, and Windows PowerShell 5.1, and deploys the GitHub release and the Gallery package from `main`. Deployment needs the `GitHubToken` and `GalleryApiToken` repository secrets.

> [!NOTE]
> Run `build.ps1` and `Invoke-Pester` in a detached process rather than the VS Code integrated terminal. See [`powershell-execution-safety.instructions.md`](com.github.copilot/rules/powershell-execution-safety.instructions.md).

## Verifying It Works

Start with `Test-CopilotAtelier` for a module or clone deployment, then verify
Discovery in the client. A local health report cannot prove that an editor has
loaded the files.

- **Agents**: In Copilot Chat, check the agents dropdown — your custom agents should appear
- **Instructions**: Type `/instructions` in chat to see the Configure Instructions menu
- **Skills**: Type `/` in chat to see skills as slash commands
- **Prompts**: Type `/` in chat to see prompt files as slash commands
- **Hooks**: Run **Developer: Show Agent Debug Logs** and look for `Load Hooks` listing `~/.copilot/hooks`; hook output goes to the **GitHub Copilot Chat Hooks** channel in the Output panel
- **Chat Customizations editor**: Click the gear icon in the Chat view (or run **Chat: Open Chat Customizations** from the Command Palette) to see all registered agents, instructions, skills, and prompts in one place
- **Debug logs**: If customizations aren't being applied, open the ellipsis (**…**) menu in the Chat view → **Show Agent Debug Logs**

## Deployment diagnostics and removal

```powershell
$report = Test-CopilotAtelier
$report.Checks | Format-Table Code, Severity, Path, Message -Wrap
Test-CopilotAtelier -Quiet
Uninstall-CopilotAtelier -WhatIf
```

Diagnostics check file hashes, version drift, Discovery targets, required hook
scripts, hook configuration, and VS Code settings without executing hooks or
changing the profile. `IsHealthy` and `-Quiet` mean no error was found; inspect
warnings for modified files, duplicate skill links, and legacy deployments.
Pass `-TargetPath` to inspect or remove a specific deployment. Ambiguous OneDrive
accounts produce an error instead of an unattended prompt.

After reviewing the preview, run `Uninstall-CopilotAtelier`. It confirms once,
removes only recorded files with matching hashes, and cleans empty managed
directories and matching Discovery links. Modified files, untracked files,
links serving retained content, settings, keybindings, environment variables,
installed module versions, and native plugins remain untouched.

Older Deployment records have no ownership hashes. Uninstall leaves them
alone; install preserves matching untracked files without claiming ownership
and refuses differing files. Hash equality alone never authorizes removal.
Back up the old tree and reconcile conflicts before updating. Never use an
older destructive installer to bypass a conflict. To roll back payload content,
use the current installer with `-ContentPath` pointing at the older module's
content, preview with `-WhatIf`, then apply after reviewing the plan. File-hash
diagnostics cover recorded owned files, not all personal or legacy content.

The safety boundary is the selected payload and deployment roots. Records and
paths are validated as data, and neither diagnostics nor deployment executes
payload content. Hashes detect drift, not authenticity: use trusted source
content and protect the deployment directory from unauthorized writers.
Concurrent or malicious same-user changes are not isolated by these checks.

## Client verification boundaries

| Component | Repository verification | Still requires client verification |
|---|---|---|
| PowerShell deployment | Sandboxed install, update, removal, links, settings, ownership, and `-WhatIf` tests | Filesystem permissions and cloud-sync behavior on the destination machine |
| VS Code Customizations | Frontmatter, catalogue, tool bounds, and configured Discovery paths | Loaded entries, actual tool availability, and executed workflow quality |
| Other Copilot clients | Shared plugin layout and portable Skill structure | Product-specific tools, model priority arrays, handoffs, and hook event behavior |
| Other Agent Skills clients | Portable Skill layout and optional skill Discovery links | Client-specific registration and runtime dependencies; no Custom agent or hook parity is implied |

The configuration gate in
[tests/CustomizationSecurity.Tests.ps1](tests/CustomizationSecurity.Tests.ps1)
rejects wildcard tools, unbounded delegation, Prompt tool expansion, unsafe
hook timeouts, and persistent remote authorization. Existing unrestricted MCP
access has a named, shrink-only baseline; passing the gate does not turn that
debt into containment. Runtime agent quality still needs behavioral evals.

## Troubleshooting Skills

If a skill in the `skills/` folder is not being discovered by VS Code, check the following:

### YAML Frontmatter Is Required

Every `SKILL.md` file **must** start with YAML frontmatter containing `name` and `description` fields. Without this, VS Code cannot register the skill.

```markdown
---
name: my-skill-name
description: >-
  A description of what the skill does. Include USE FOR and DO NOT USE FOR
  trigger phrases to help Copilot know when to load it.
---

# Skill Title

Content starts here...
```

### Blank Line After Frontmatter

There **must** be a blank line between the closing `---` delimiter and the first line of content. Some parsers fail to separate the metadata from the document body without it.

**Correct:**

```markdown
---
name: my-skill
description: >-
  My skill description.
---

# My Skill
```

**Incorrect:**

```markdown
---
name: my-skill
description: >-
  My skill description.
---
# My Skill
```

### Reload Required

After adding or fixing a skill file, you must **reload VS Code** (or start a new chat session) for the skill to be discovered.

### Verifying Skills Are Loaded

To confirm a skill is registered:

1. In the Chat view, click the gear icon (**Configure Chat**) — or run **Chat: Open Chat Customizations** from the Command Palette
2. Select the **Skills** tab and look for your skill in the list
3. Alternatively, type `/skills` in chat to open the Configure Skills menu

If a skill doesn't appear, open the ellipsis (**…**) menu in the Chat view and choose **Show Agent Debug Logs** to see why it failed to load (usually a frontmatter or `name`/directory mismatch).

## Useful Chat Shortcuts

| Command | Action |
|---|---|
| `/agents` | Configure Custom Agents menu |
| `/instructions` | Configure Instructions and Rules menu |
| `/skills` | Configure Skills menu |
| `/prompts` | Configure Prompt Files menu |
| `/init` | Generate workspace instructions from your codebase |

## Reference

- [`reference/copilot-cli-model-routing.md`](reference/copilot-cli-model-routing.md) — 4-tier model-routing policy for the GitHub Copilot CLI (Executors / Implementers / Tech Leads / Architects). Reference-only; not auto-attached. The document was written against the early-2026 lineup; a banner at the top maps the older model IDs (Opus 4.5 / 4.6, GPT-5.1) to the current ones (Opus 4.8, GPT-5.4 / 5.5). A full rewrite is still outstanding.
- [`reference/howto-write-skills.md`](reference/howto-write-skills.md) — condensed two-page primer for authoring `skills/**/SKILL.md` files: the six-step frame (Name/Trigger/Outcome/Dependencies/Step-by-step/Edge cases), five high-leverage rules, hard limits (1024-char description, 500-line body), description shape, degrees of freedom, eval-driven development, anti-patterns, and links to the canonical Anthropic Agent Skills docs/PDF/engineering blog plus the `anthropics/skills` repo. Pairs with [`skills/skill-creator/SKILL.md`](skills/skill-creator/SKILL.md) (the full operating manual, auto-loaded when a skill-authoring task triggers).

## Featured In

- [**The Agentic Operating Model**](https://github.com/raandree/AgenticOperatingModel) — a 1h/2h/4h presentation and workshop on versioned, agent-assisted knowledge work. CopilotAtelier is used as the reference exemplar of a mature personal atelier (Module 3 — *Your Atelier — Customization as Code*; Module 8 — *A Mature Personal Atelier*) and as the cross-machine instruction-sync pattern. The workshop also publishes complementary, project-level material that pairs well with this repo:
  - [Agentic Knowledge-Work Patterns](https://github.com/raandree/AgenticOperatingModel/blob/main/content/materials/agentic-knowledge-work-patterns.md) — ten reusable patterns for applying the operating model beyond code.
  - [Memory Bank Template](https://github.com/raandree/AgenticOperatingModel/tree/main/content/materials/memory-bank-template) — a tool-neutral starter set for per-project memory banks.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
