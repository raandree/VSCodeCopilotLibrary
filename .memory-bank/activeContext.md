---
status: current
last-verified: 2026-09-05
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Native deployment safety and diagnostics are implemented on
`ai/deployment-safety-and-diagnostics`. Installation records owned file hashes,
preserves untracked content, refuses conflicts and overlapping source trees,
and rechecks writes. Matching bytes alone never confer ownership. Diagnostics
are read-only; uninstall removes only unchanged owned files and preserves
personal content and configuration. Root-scoped guards support parent aliases.

SessionStart context is bounded without a hook-off switch. The configuration
gate checks tools, delegation, Prompt overrides, and hook limits, with twelve
named unrestricted-MCP exceptions. Usage Prompt YAML is repaired. Relative
source paths resolve through PowerShell before filesystem planning.

Build and full test gates pass: 1,137 passed, 60 existing skips, 83.63% coverage
against 65%. Windows PowerShell 5.1: 264 passed, one platform skip. Parsing,
PSScriptAnalyzer, Markdown lint/rendering, and diff checks are clean. Pester is
pinned to 5.7.1; result export retains paths and labels instead of traversing
live provider metadata. One pre-existing simulated-backend warning remains.
No active profile was changed and nothing was pushed. Live cloud sync and
non-Windows clients were not exercised; `review: on` is recommended before
publishing the new removal API and deployment ownership boundary.

## Previous focus: role-record migration

Legacy role records use metadata-only planning, whole-plan validation, and
verified copies without overwriting or deleting sources. The three role agents
require explicit decisions and preview with `-WhatIf`. The migration shipped
in `e23eb7e`; focused tests passed 27/27 and the full gate passed 1,057 with
78.51% coverage. Behavioral cases remain unexecuted without a model backend.
Installation never owns those private repository records. Details are in the
changelog and `skills/memory-bank/notes-evals.md`.

## Previously: the `long-running-job-monitor` discovery failure

A 45-minute live Hyper-V proof ran in another workspace with the Skill never
loaded: no cadence tick, thirty silent minutes, two mid-job turns with no status
line. Every rule it broke was already written down correctly, so the defect is
discovery, not content. Two lessons generalise. A `USE FOR:` list must carry the
words the user's own glossary uses — that workspace says *proof*, the list said
"live test". And guidance that sits downstream of the step it constrains does not
bind that step: arming the tick lived in a later section, so an agent could
follow the launch step exactly and still end the turn with nothing armed.

## Earlier: the runaway `cycle: full` chain

Fifteen complete `software-engineer` ↔ `security-reviewer` round trips in one
session, 30 MB against a ~600 KB norm. Both handoff legs auto-submitted and the
only bound was prose — a cap neither side could count, because a handoff starts
the receiving agent with fresh context. Any ring of `send: true` handoffs is
unbounded by construction, so *Fix Issues Found* now sets `send: false` and
`tests/DevelopmentCycle.Tests.ps1` walks the whole graph and fails on one.

## Agent Plugins 1.0 status

The latest VS Code Agent Plugins documentation confirms all four Copilot-only
component paths under `com.github.copilot/`, including `rules/` and `commands/`.
The source layout chosen in Decision 0023 is therefore documented upstream;
only the accepted cross-type-link mismatch in the translated module deployment
remains.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and fully restored from git; no corruption reached a commit.

- It is asynchronous. The script's own byte-exact read-back verification passed
  for all 175 files, and `git diff` showed the corruption afterwards, so the
  rewrite lands after the write returns. A verify-after-write loop cannot
  detect it.
- A single-file scripted write was clean, so it correlates with volume.
- Every `replace_string_in_file` edit was clean, across roughly forty files.

Until the cause is found, edit files through the editor tooling, and treat any
scripted bulk rewrite of this tree as unsafe. `git grep -l -e nnkteuotnon -e\naeelyTo` detects it in one pass.

## Blocked, not deferred

The ShellPilot module and `Invoke-ShpBatch` are absent on this machine, so
`-Mode Execute` is unavailable for both eval harnesses. That blocks the two
measurement items outright rather than by choice of priority:

- The 75 prepared route-selection prompts cannot be answered, so no
  pass@k or pass^k result exists yet.
- The seven authored trigger-query sets cannot be swept, so `german-tax-research`
  and the other 37 baselined Skills stay unmeasured for discovery.

Both need ShellPilot plus a paid model backend, and a sweep costs money, so the
run needs an explicit go-ahead rather than an assumption.

## Open findings

- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  that can read the repository and use web, GitHub, MCP, and terminal tools.
  Prose does not enforce the boundary, especially on native Windows where VS
  Code terminal sandboxing is unavailable.
- **High:** eleven older agents combine workspace/private-data access,
  untrusted web content, arbitrary execution, and broad MCP access. Replace
  copied omnibus tool lists with role-specific least-privilege surfaces. The
  README now documents staged private intake, local transformation, minimized
  public research, and user-confirmed browser actions, but guidance is not
  enforced containment.
- **Medium:** Security Reviewer and Technical Writer delegate research to the
  full `research-analyst` profile, whose tools include edit, terminal, browser,
  GitHub, and MCP access. Their research-only delegation needs a narrower
  read-only code explorer and a separate public-source researcher.
- **Medium:** twelve agents now expose `browser`, but only Software Engineer
  carries an explicit ephemeral-loopback, shared-authentication, and
  user-confirmation contract. The hard-coded browser allow-list proves tool
  presence, not role need or safe behavior; review it role by role.
- **Major:** `career-coach` (35,672 chars), `research-analyst` (43,376),
  `security-reviewer` (43,772), and `technical-writer` (35,018) exceed GitHub's
  30,000-character Custom agent prompt limit. The new test prevents growth; the
  separate Session handoff owns the refactor below the limit.
- **Major:** every profile omits `target` but declares a VS Code model-priority
  array and mostly VS Code-qualified tool IDs. Copilot CLI documents one model
  string plus CLI tool names such as `view`, `edit`, `powershell`, `grep`, and
  `task`; the README now warns that discovery is not capability parity, but
  product-specific profiles or a shared compatible subset remain open.
- **Medium:** no executed agent behavioral eval set exists. The semantic tests
  catch structural regressions, but the Chat Customizations Evaluations
  extension is not installed and no live capability comparison was run.
- **Low:** three test files parse agent frontmatter with independent regular
  expressions. `powershell-yaml` is already available to the test suite; one
  shared parser plus malformed nested fixtures would reduce false greens.
- **Low:** the full build reports one warning for an intentionally simulated
  trigger-eval backend failure. Expected failure output should be captured by
  its test so a clean build has no warning that can mask a new one.

## Carried forward from the route-selection eval

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes, and `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label
  leakage, fallback, strict shape, reliability aggregation, and failure
  accounting.
- The first stage infers routes and fallback only; the deterministic resolver
  still receives human labels for `durableWrite`, role files, and Decision
  records.
- Context-window cost, latency, and answer quality under routed versus full
  loading remain unmeasured. Safety is gameable on its own \u2014 a reply naming
  every route never misses \u2014 and no precision floor is set, so `Passed = True`
  at low precision is not yet a failing build.

## Carried forward from earlier focuses

- `WindowsAccessControl` slots 1 and 2 use the older ink-variant reading of
  dark/light, so two sets in one shared library disagree on "dark mode". That
  repository is not in this workspace.
- The `brand-logo-system` integration step was measured on one project only.
- The `skill-creator` description edit remains unproven: train reached 100 %
  while validation fell, which is the overfitting signal.

## Next step

The job-monitor changes remain staged on the updated `main`. When a behavioral
runner is available, execute the authored migration cases before claiming
pass@k or pass^k. The oversized Custom agent refactor remains in its separate
Session handoff.
