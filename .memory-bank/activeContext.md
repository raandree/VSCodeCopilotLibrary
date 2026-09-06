---
status: current
last-verified: 2026-09-06
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Completed implementation and focused independent re-review for M1-M5 and L1-L6 on
`ai/deployment-safety-and-diagnostics`, starting at clean `abf8970`. Leave all
changes uncommitted. The user requested implementation and a focused independent
re-review, not publication or the separate agent-permission/CLI backlog.

All eleven findings have implementations and focused regressions. Hook scripts
and commands are checked against the loaded module; repair remains recorded-file
only; recoverable pending operations require verified staging before completion
can be inferred. Concurrent matching untracked files are not adopted. Filename
identity and segment validation are shared. Destinations, legacy diagnostics,
type-data restoration, strict hook JSON, and static Prompt policy are covered.
The Glossary defines Owned file and Deployment plan.

Full detached build/test: 1,234 passed, zero failures, 66 explained skips,
87.8% coverage; 20 tasks, zero errors, one existing simulated-backend warning.
Windows PowerShell 5.1: 473 passed/nine skips, plus the final six serialization
checks passed after the fixture-only adjustment. All 22 changed scripts pass
native AST and PSScriptAnalyzer. Pinned uv 0.8.15 executed 47 reference checks;
only two documented divergence skips remain. Earlier serialization defects
found by the full gate have regression guards; expected child failures no
longer contaminate parent build accounting.

Independent security-reviewer decision: Approve, zero Blocker/Major, two Minor
and three Nit observations retained in `assessment-log.md`. The filename
probe's fail-closed prerequisite is documented. Non-Windows and live OneDrive
remain unverified: no WSL distribution, Docker, or Podman is installed, and no
authorized sync test account is available. Model-backed evaluations remain
unrun without a supported runner and spending permission.

The earlier CONDITIONAL review did not close the findings. Prior wording that
called them accepted residual risk was not user acceptance and is superseded.
Historical runs (1,137 passed/60 skips/83.63% and 264 passed/1 skip on 5.1)
remain historical evidence, not validation of these edits. The per-ID ledger
and log names are in `assessment-log.md`.

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

- **Deployment review:** M1-M5 and L1-L6 are implemented and independently
  approved on the verified scope. Non-Windows/cloud-sync execution and the
  review's non-blocking observations remain explicitly disclosed, not waived.
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

Await the user's review of the uncommitted remediation. No commit, merge,
publication, push, or broader-backlog work is authorized. Non-Windows and live
OneDrive verification need isolated environments before they can be claimed.
