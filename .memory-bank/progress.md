---
status: current
last-verified: 2026-09-05
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v4.0.0`
(2026-08-26), whose changelog section landed on `main` in #22. Incremental work
is tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-09-05**: Implemented hash-aware deployment and conservative removal,
  read-only diagnostics, bounded SessionStart context, and configuration gates.
  Added ownership, path, concurrency, serialization, and security regressions;
  repaired usage Prompt YAML and pinned Pester 5.7.1. Build/test: 1,137 passed,
  60 existing skips, 83.63% coverage; Windows PowerShell 5.1: 264 passed, one
  platform skip. Changes remain on a local topic branch; no active profile or
  remote was changed. One pre-existing simulated-backend warning remains.

- **2026-09-04**: Reconciled the job-monitor change with `main` at `e23eb7e`.
  Execution-safety now loads the Skill at command launch, including
  agent-initiated runs, binds detachment to monitoring, and names all four
  observed anti-patterns. Description: 989 chars. Earlier validation:
  960 tests passed. Recorded description eval: train 5/7 to 6/7, validation
  4/5 in both arms; agent-initiated selection remained 0/3.

- **2026-09-04**: Added a repository-scoped, plan-then-apply migration for
  legacy career, legal, and tax Memory Bank records. Planning is read-only by
  default; ambiguous files require explicit assignment; apply validates the
  whole plan, rejects path and reparse-point escapes, copies bytes exactly,
  verifies SHA-256, preserves every source, and is idempotent. The three role
  agents now invoke this workflow before creating namespaced replacements.
  Validation: migration 27/27 and full build 1,057 passed, 0 failed, 61
  skipped, 78.51% coverage. Behavioral cases are authored but unrun because no
  Waza, ShellPilot, or model backend is installed. The source turn left the
  changes uncommitted by request; they are now commit `e23eb7e` on `main`.

- **2026-09-04**: Audited all 16 Custom agents against current first-party and
  OWASP guidance, then repaired the structural findings: executable delegation
  for Security Reviewer and Technical Writer, real DevOps subagent composition,
  removal of a targetless Research Analyst handoff, role-namespaced career,
  legal, and tax records, and `browser` in every web-capable profile. Added 24
  semantic contracts, including a 30,000-character limit with a shrink-only
  baseline, plus cross-client and sensitive-data guidance. The semantic suite
  passes 24/24; the full detached build passes 1,029 tests, 0 failures, 61
  skips, and 78.51% coverage. Prompt-size work has its own forward Session
  handoff; the security containment redesign remains open. The source turn left
  the changes uncommitted as requested; they are now commit `5e603b7` on `main`
  and `origin/main`.

- **2026-09-04**: Replaced `openSimpleBrowser` with VS Code's built-in
  `browser` tool set in the Software Engineer Custom agent and added a closed
  reproduce-inspect-fix-repeat loop for web applications. Browser use defaults
  to ephemeral loopback sessions, authenticated tabs require explicit sharing,
  and the Contoso overlay remains no-egress. Validation: 138 focused contracts,
  native build 1,005 passed, 0 failed, 61 skipped, 78.51% coverage; deployed
  user-level file matches the source SHA-256 exactly.

- **2026-09-02**: Added the generic `/complete-specifications` Prompt-led
  workflow with capability-isolated controller, implementer, and reviewer
  agents. Live mode defaults off; controller/worker egress is empty; an external
  profile/verifier/appender owns containment and tamper-evident evidence. The
  shared hook now resolves exact deployment paths and covers common Git/GitHub
  CLI option forms. Validation: 237 focused tests; native build 957 passed,
  0 failed, 108 environment-declared skips, 78.86% coverage; independent
  security gate 0 Critical/High. Decision 0025 records the architecture.

- **2026-09-02**: Deleted the `.github/hooks` smoke-test probe, which had been
  failing on every turn since 2026-08-10. Its `windows` override hardcoded
  `D:\Git\CopilotAtelier\...`, the drive the repo sat on when it was written,
  and that override wins on Windows. It survived because `Hooks.Tests.ps1`
  asserts exactly this failure but is scoped to
  `com.github.copilot/hooks/hooks.json`; a second hook file one directory away
  was outside every gate.

- **2026-09-02**: Added a session clock so Post-flight closes with the chat's
  measured elapsed duration. A model has no clock, so the number is written to
  disk by `Add-SessionContext.ps1` at
  `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json` and read
  back by `Get-SessionElapsed.ps1`, which the agent runs last and copies
  verbatim. The first attempt printed it from the `Stop` hook and was rejected
  on sight: VS Code renders a hook `systemMessage` as a detached, collapsed
  warning box, so the line was beside the checklist, not in it. A hook cannot
  write inside the reply and a model cannot read a clock, so the split is
  forced. `Write-SessionClose.ps1` keeps the turn counter and now speaks only
  when the clock is unreadable. `UserPromptSubmit` was ruled out — common output
  format only, no `additionalContext` — and `PreToolUse` was rejected as a token
  cost on every call. Decision record 0024, revised the same day.

- **2026-09-01**: Fixed job-monitor discovery and same-turn heartbeat arming,
  and bounded the development-cycle handoff graph by making the reviewer's
  return user-gated. The changelog retains the incidents and detailed evidence.

## Stable capabilities

- Deterministic lifecycle hooks that block remote mutation and prove Memory Bank
  presence without relying on model compliance.
- Screenshot documentation for modifiable Windows applications, existing or
  third-party executables without source access, and windows the user already
  has open.
- One-command, idempotent Setup script with Windows, macOS, and Linux path
  handling.
- One Canonical target exposed through `~/.copilot` Discovery links, with
  opt-in Claude Code and Agent Skills links.
- Agent plugin packaging for installation from a Git URL.
- Role-specific Custom agents with Agent-to-agent handoffs, model priority
  arrays, and explicit subagent eligibility.
- File-scoped Instructions and on-demand Skills with declared environment
  requirements.
- Prompt templates for repeatable development, research, legal, and operations
  workflows.
- Detached Pester and build execution with persistent completion evidence.
- Test-first behavior changes, regression guards, risk-scaled review, and
  agentic-security checks.
- Routed Memory Bank loading with deterministic non-inferiority, health,
  provenance, compactness, and rollback checks.

## Open work

- Split research delegation into a read-only code explorer and a public-source
  researcher instead of granting the full `research-analyst` tool surface.
- Review the twelve-agent browser allow-list role by role and add explicit
  public, authenticated, credential, upload, and irreversible-action bounds to
  every retained browser workflow.
- Replace the three handwritten agent-frontmatter parsers with one shared YAML
  parser and fixtures that prove malformed nested handoffs and lists fail.
- Capture the trigger-eval harness's expected simulated backend failure so the
  successful full build emits no warning.
- Restore a Windows PowerShell 5.1 CI leg now that `Repair_ManifestEncoding`
  fixes the manifest instead of working around it. The leg was dropped
  2026-07-29 for the defect this fix closes; re-adding it guards the fix and
  needs the `ci.yml` `shell: pwsh` steps distinguished from `powershell.exe`.
- Run the seven shipped trigger-query sets, then cover the 38 Skills still on
  the `SkillTriggerCoverage` uncovered baseline. The sets are authored but
  unmeasured, so the gate currently proves only that the queries exist. Execute
  mode needs ShellPilot plus a paid backend, neither present on this machine.
- Split the nine Skills still on the `SkillFrontmatter` over-budget baseline
  into bodies under 500 lines plus one-level references, one per change,
  removing each from the baseline as it lands. `german-legal-research` at 780
  body lines is the next worst.
- Continue splitting oversized auto-applied Instructions into concise enforced
  rules plus on-demand Skill references where that can be done without losing
  behavior.
- Keep Custom agent bodies within explicit prompt budgets and add deterministic
  regression checks for other frequently used agents.
- Extend the routing eval set when real retrieval failures are observed.
- Add Markdown linting to continuous integration when the required runtime is
  available.
- Review model identifiers when Copilot model availability changes; the last
  entry of every agent `model` array must stay GA.
- Evaluate the remaining VS Code surfaces that no Customization covers yet:
  the agent host and its harness selection, `chat.assistedPermissions.enabled`,
  and organization-level instructions and agents.
- Curate `techContext.md` and `systemPatterns.md` when either approaches its
  line budget; `systemPatterns.md` runs close to its 110-line cap, so any new
  Decision record or relationship needs a trim in the same edit.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
