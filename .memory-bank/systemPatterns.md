---
status: current
last-verified: 2026-09-06
owner: software-engineer
source: .memory-bank/decisions and source/
---

# System patterns

Durable relationships and the Decision record index. Read a linked record only
when the task needs its rationale or consequences. The repository layout lives
in `techContext.md`, not here.

## Decision index

| # | Decision record | Status | Date |
|---|---|---|---|
| 1 | [Use OneDrive when available](decisions/0001-use-onedrive-sync.md) | Accepted | 2026-04-23 |
| 2 | [Parse JSONC-tolerant settings](decisions/0002-parse-jsonc-settings.md) | Accepted | 2026-04-23 |
| 3 | [Preserve unrelated location settings](decisions/0003-preserve-location-settings.md) | Accepted | 2026-04-23 |
| 4 | [Use Agent-to-agent handoffs](decisions/0004-use-agent-handoffs.md) | Accepted | 2026-04-23 |
| 5 | [Scope Instructions with applyTo](decisions/0005-scope-instructions-with-applyto.md) | Accepted | 2026-04-23 |
| 6 | [Require Skill frontmatter](decisions/0006-require-skill-frontmatter.md) | Accepted | 2026-04-23 |
| 7 | [Use Claude Opus 4.8](decisions/0007-use-claude-opus-4-8.md) | Accepted | 2026-07-02 |
| 8 | [Store Session handoffs separately](decisions/0008-store-session-handoffs.md) | Accepted | 2026-05-27 |
| 9 | [Codify the Markdown house style](decisions/0009-codify-markdown-style.md) | Accepted | 2026-07-02 |
| 10 | [Detach long-running PowerShell](decisions/0010-detach-long-running-powershell.md) | Accepted | 2026-07-07 |
| 11 | [Exempt Non-impacting turns](decisions/0011-exempt-non-impacting-turns.md) | Accepted | 2026-07-16 |
| 12 | [Govern the Ubiquitous Language](decisions/0012-govern-ubiquitous-language.md) | Accepted | 2026-07-22 |
| 13 | [Centralize shared lifecycle behavior](decisions/0013-centralize-shared-lifecycle.md) | Accepted | 2026-07-24 |
| 14 | [Prove Memory Bank routing](decisions/0014-prove-memory-bank-routing.md) | Accepted | 2026-07-24 |
| 15 | [Keep native memory role-gated](decisions/0015-keep-native-memory-role-gated.md) | Accepted | 2026-07-24 |
| 16 | [Enforce house rules with hooks](decisions/0016-enforce-house-rules-with-hooks.md) | Accepted | 2026-07-28 |
| 17 | [Keep MCP curation out of scope](decisions/0017-keep-mcp-curation-out-of-scope.md) | Accepted | 2026-07-28 |
| 18 | [Distribute as a Sampler-built PowerShell module](decisions/0018-distribute-as-powershell-module.md) | Accepted | 2026-07-29 |
| 19 | [Gate Skills on the reference validator](decisions/0019-gate-skills-on-the-reference-validator.md) | Accepted | 2026-08-11 |
| 20 | [Refuse a lossy customization merge](decisions/0020-refuse-lossy-customization-merges.md) | Accepted | 2026-08-11 |
| 21 | [Checkpoint the session before compaction](decisions/0021-checkpoint-before-compaction.md) | Accepted | 2026-08-25 |
| 22 | [Own the pre-code phase with a Custom agent](decisions/0022-own-pre-code-phase-with-agent.md) | Accepted | 2026-08-26 |
| 23 | [Adopt Agent Plugins 1.0 without moving Instructions and Prompts](decisions/0023-adopt-agent-plugins-1-0.md) | Accepted | 2026-08-26 |
| 24 | [Measure the session clock in a hook, not in the model](decisions/0024-measure-the-session-clock-in-a-hook.md) | Accepted | 2026-09-02 |
| 25 | [Package specification completion as capability-isolated agents](decisions/0025-package-specification-completion-as-capability-isolated-agents.md) | Accepted | 2026-09-02 |

## Live relationships

- Agent conformance has three independent gates: schema validity, executable
    behavior, and effective containment. A passing frontmatter parser or exact
    tool-list fingerprint proves only the first.
- A no-egress claim is transitive across terminal commands, subagents, handoffs,
    MCP tools, and hooks. Every reachable execution context needs an enforced
    empty allow-list; prose and omitted web tools are not containment.
- Sensitive-data research is staged: narrow read-only intake, local
    transformation, minimized public research, then explicitly shared
    authenticated actions. Tool availability is capability, not authorization;
    prompt guidance does not replace an OS-enforced boundary.
- The `agents` property authorizes which Custom agents may run as subagents; it
    does not inherit their bodies. Share instructions through an actual referenced
    Instruction or inline with a drift test when composition is unavailable.
- Copilot-specific plugin agents are read by VS Code, Copilot CLI, and the
    Copilot app. Cross-client bodies, model fields, and tool names satisfy the
    strictest shared contract; otherwise declare an intentional `target` and
    ship a compatible counterpart.
- The Software Engineer uses `browser` for ephemeral loopback validation;
    authenticated state requires explicit sharing.
- A handoff cycle is bounded in frontmatter, not prose: any ring made entirely
    of `send: true` edges can run unattended and must fail a graph test.
- Costly independent review is a user-set switch with a named default. The
    shared Definition of Done records deferred high-risk review explicitly.
- The module carries the Customizations as payload; the installer translates
    Agent Plugins paths into the five `~/.copilot` Discovery siblings.
- File equality is not deployment ownership. Preserve untracked matches;
    removal requires both a recorded relative path and matching bytes. Source
    and deployment trees must not overlap.
- Persist each pending file operation before atomic replacement and checkpoint
    it afterwards. Recovery reconciles observed hashes, not assumed completion;
    local exclusive handles coordinate callers, not cross-machine cloud sync.
- Validate paths at and below the selected root, including non-directory
    ancestors and reparse points. Trusted parent aliases are outside that
    boundary; hash checks are not an atomic transaction or a sandbox.
- Hooks enforce unconditional rules; Instructions carry judgement calls. Hook
    commands resolve exact trusted roots, avoid pre-parse `$` substitution, and
    fail closed only for security controls.
- A gate that can skip is not a gate. External checks must fail in CI and prove
    they reject a bad fixture.
- Known debt is a shrink-only baseline keyed to each offender, never a disabled
    check or a silently growing allowance.
- A Skill cannot override a Custom agent body or grant a missing tool. A
    conflicting discipline needs its own capability-bounded persona.
- Role-record migration is repository-selected and split into metadata-only
    planning plus whole-plan-validated apply. Ambiguous records need a user
    decision; apply copies and verifies bytes but never moves or deletes sources.
- Memory Bank routing has deterministic and label-free eval layers. Compaction
    bypasses both lifecycle gates, so `PreCompact` writes the anchor Pre-flight
    reloads.
- Agent Plugins and module deployment have irreconcilable layouts. Cross-type
    relative links resolve in only one view; functional loading cannot depend on
    them.
