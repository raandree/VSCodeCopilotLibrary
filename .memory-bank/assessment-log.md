---
status: current
last-verified: 2026-09-06
owner: security-reviewer
source: security assessments of this repository
---

# Assessment log

Episodic record of completed security assessments. One entry per assessment:
date, scope, verdict, and the findings that outlived the review. Retain two
years; archive older entries to a dated Memory Bank topic.

## 2026-09-06 — deployment lifecycle and configuration gates (`8353cef`)

**Scope.** `Install-CopilotAtelier` ownership rewrite, new `Test-CopilotAtelier`
and `Uninstall-CopilotAtelier`, three new private deployment helpers,
`Add-SessionContext.ps1` context budget, the Customization configuration gate,
and the Sampler result-serialization task.

**Verdict: CONDITIONAL.** No Critical or High findings. The change set removes a
real destructive-overwrite path and adds path, ownership, and conflict
validation. Five Medium findings remain; two of them bear directly on publishing
the removal and diagnostic commands.

**Findings that outlived the review.**

- Drift of a deployed security control is reported as a non-failing `Warning`.
  Deleting `Block-RemoteMutation.ps1` is an `Error`; neutering its body is not,
  and `IsHealthy` stays true. `InvalidHookConfiguration` only asserts that the
  four event keys are truthy, so a repointed hook command also passes.
- Conservative ownership has no repair path. A drifted owned file blocks its own
  reinstallation and `-Force` deliberately does not override, so a tampered hook
  script cannot be restored by supported means.
- Apply is not transactional. Settings are written before the file loop and the
  Deployment record after it, so a mid-loop throw leaves record and disk
  disagreeing. A later payload downgrade turns that into a permanent conflict.
- Record write-side and read-side validation are asymmetric. The plan accepts
  POSIX-legal names that the record reader later rejects, which can make a
  successful deployment permanently unreadable.
- Traversal rejection in the record reader depends implicitly on the
  trailing-dot segment rule rather than an explicit `..` check.

**Carried forward, not introduced here.** The twelve agents with unrestricted
MCP access are now baselined by the configuration gate but not contained; the
`software-engineer-contoso` egress claim and the broad omnibus tool surfaces
recorded in `activeContext.md` remain open.

**Not exercised.** Live OneDrive sync, non-Windows hosts, concurrent
install/uninstall, and any behavioral eval of the shipped Customizations.
