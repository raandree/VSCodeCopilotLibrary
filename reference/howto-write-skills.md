# How to Write Skills — Condensed Guide

A compact primer for authoring `skills/**/SKILL.md` files in this repository. The full operating manual lives in [`skills/skill-creator/SKILL.md`](../skills/skill-creator/SKILL.md); this page is the short version with links to the canonical external sources.

## What a Skill is

A folder with a `SKILL.md` (YAML frontmatter + markdown body) plus optional `references/`, `scripts/`, and `assets/`. Claude pre-loads only the `name` + `description` from every installed skill; it reads the body when the skill triggers, and reads `references/` files only when the body points to them. This is the **progressive disclosure** model — three loading tiers, three context-cost tiers.

Progressive disclosure is the skills-level application of **context engineering** — the discipline of curating what enters the model's finite context window and when, so the agent sees exactly the information a step needs and nothing more. On-demand reference loading, tight descriptions, and the 500-line body cap are all context engineering: they keep dozens of skills available at a near-zero idle cost and pay the token price only when a skill actually fires.

```text
skills/<kebab-name>/
├── SKILL.md         (required — ≤ 500 lines, description ≤ 1024 chars)
├── references/      (loaded on demand, one level deep from SKILL.md)
├── scripts/         (executed via shell; code never enters context)
└── assets/          (templates, sample inputs, expected outputs)
```

## The six-step frame

Use this before writing a single line of SKILL.md. If any step is unclear, the skill scope is wrong — refine, then start.

1. **Name** — kebab-case, ≤ 64 chars, no `claude` / `anthropic`.
2. **Trigger** — the `description` Claude reads to decide whether to load. Get this wrong and the skill never activates.
3. **Outcome** — what "done" looks like, in one sentence.
4. **Dependencies** — every tool, MCP server, reference, script, or asset the skill needs.
5. **Step-by-step** — the exact instructions Claude follows in order, with human-in-the-loop checkpoints where applicable.
6. **Edge cases** — what happens when input is vague, missing, oversized, or unexpected.

## Five high-leverage rules

1. **Description is the only thing the selector sees.** Body text never influences triggering. When a skill under-triggers, fix the description first.
2. **Third-person voice for the capability, imperative for the trigger.** `"Extracts text from PDF files. Use this skill when the user has a PDF and wants its contents."` Never first person (`"I can help you..."`) and never addressed to the user (`"You can use this to..."`) — POV-inconsistent text breaks discovery, and the imperative is aimed at the agent, which is a different thing. The two upstream guides phrase this rule differently; [`skill-creator`](../skills/skill-creator/SKILL.md) reconciles them.
3. **Point, don't dump.** SKILL.md is the standard operating procedure. Deep knowledge (XML schemas, API tables, long examples) belongs in `references/<topic>.md`. When the body crosses 500 lines, split.
4. **References one level deep.** Claude often previews nested references with `head -100` and gets incomplete content. All references link directly from SKILL.md.
5. **Pick a default.** Don't offer five libraries — pick one and mention alternatives only as documented escape hatches ("use X instead when Y").

## Hard limits

| Limit | Value | Failure mode |
|---|---|---|
| `name` length | ≤ 64 chars | Skill silently rejected |
| `description` length | ≤ 1024 chars | GitHub Copilot CLI silently drops the skill |
| SKILL.md body | ≤ 500 lines | Context bloat; degraded selection accuracy |
| Reference file with TOC required | > 100 lines | Partial reads miss content |

Verify description length:

```powershell
(Get-Content SKILL.md -Raw -Encoding utf8 |
    Select-String -Pattern 'description:\s*>-\s*(.+?)(?=\n---)' -AllMatches
).Matches[0].Groups[1].Value.Length
```

## The description shape that triggers reliably

```yaml
description: >-
  One-sentence third-person summary of what the skill does, followed by an
  imperative trigger clause ("Use this skill when ..."). Applies even when the
  user does not name the domain.
  USE FOR: the general categories of request this skill serves.
  DO NOT USE FOR: adjacent skill (use other-skill instead), near-miss request
  that belongs elsewhere.
```

`USE FOR:` is a compact scope list at the level of **categories**, not a transcript of phrasings — but state those categories in the vocabulary of the domain, because the specification asks for "specific keywords that help agents identify relevant tasks". What overfits is the verbatim wording of queries that failed to trigger, not the domain terms themselves. Be pushy about listing contexts where the skill applies even when the user does not name the domain. `DO NOT USE FOR:` is the single highest-leverage anti-cannibalisation tool when two skills overlap, and it is what upstream means by "clarify the boundary between this skill and adjacent capabilities".

Selector mechanics are not publicly documented, so assume neither lexical matching nor semantic matching. Category-level scope that carries the domain's own vocabulary, plus an explicit boundary, holds either way; an exhaustive keyword dump only helps under an assumption nobody here has evidenced.

## Degrees of freedom

Match the level of specificity to the task's fragility.

| Freedom | When | Pattern |
|---|---|---|
| **High** | Multiple approaches valid | Prose checklist |
| **Medium** | Preferred pattern exists | Pseudocode or parameterised script |
| **Low** | Fragile / destructive / must be exact | Exact command, "do not modify" |

Analogy: narrow bridge with cliffs → guardrails (low freedom); open field → general direction (high freedom). Database migrations are bridges; code reviews are fields.

## Evaluation-driven development (the part most people skip)

1. Run Claude on three representative tasks **without** the skill. Document every failure.
2. Write three eval prompts in the user's exact phrasing. Save to `notes-evals.md` in the skill folder.
3. Establish baseline output.
4. Write minimal SKILL.md — just enough to fix the documented gaps.
5. Re-run with the skill loaded. Verify it triggered (PRE-FLIGHT line names it).
6. Iterate. Under-triggered → fix description. Triggered but bad output → fix body or references.

## Anti-patterns

- Vague description. ("Helps with documents." Names no category worth matching.)
- **Overfitting to failed queries.** Pasting the verbatim wording of eval queries that did not trigger. The description then works on those exact strings and nothing near them. Generalise instead — name the category those queries represent, and keep the vocabulary that belongs to it. See the trigger-eval loop in [`skill-creator`](../skills/skill-creator/SKILL.md).
- Body holds the trigger. (Body is invisible to the selector.)
- Time-sensitive language in main content. (Use `<details><summary>Old patterns</summary>` blocks.)
- Inconsistent terminology. (Pick one term and use it throughout.)
- Offering too many options. (Pick a default.)
- Deeply nested references. (SKILL.md → `a.md` → `b.md` → `c.md`. Flatten.)
- SKILL.md as tutorial. (It is reference material for an LLM that knows the domain. Cut introductions.)
- Folder name mismatches `name:` field. (CLI silently ignores the skill.)

## Canonical references

External sources, in order of authority:

1. **Agent Skills — the open standard.** The format is vendor-neutral, and these five pages are the primary authority. <https://agentskills.io/>
   - [Specification](https://agentskills.io/specification) — frontmatter fields and their constraints, directory layout, progressive disclosure, the `skills-ref` reference validator.
   - [Best practices for skill creators](https://agentskills.io/skill-creation/best-practices) — scoping, degrees of freedom, gotchas, instruction patterns.
   - [Optimizing skill descriptions](https://agentskills.io/skill-creation/optimizing-descriptions) — trigger evals, the 60/40 train/validation split, the optimisation loop.
   - [Evaluating skill output quality](https://agentskills.io/skill-creation/evaluating-skills) — test cases, assertions, grading, benchmark deltas.
   - [Using scripts in skills](https://agentskills.io/skill-creation/using-scripts) — non-interactive interfaces, `--help`, structured output, exit codes, inline dependencies.
2. **Anthropic — Skill authoring best practices.** The same material from the vendor that originated the format, and the source of the "always write in third person" warning and the gerund naming convention. <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
3. **Anthropic — Agent Skills overview.** Architecture, three-tier loading, how the agent reads SKILL.md via bash, security model. <https://platform.claude.com/docs/en/agents-and-tools/agent-skills>
4. **VS Code — Use Agent Skills.** The client surface this repository targets: skill locations, slash commands, and the `context`, `user-invocable`, `disable-model-invocation`, and `argument-hint` fields the open standard does not define. <https://code.visualstudio.com/docs/copilot/customization/agent-skills>
5. **anthropics/skills (GitHub).** Anthropic's own reference skills (`pptx`, `xlsx`, `docx`, `pdf`, Claude API). Reading these is the fastest way to see canonical structure in practice. <https://github.com/anthropics/skills>
6. **Anthropic — The Complete Guide to Building Skills for Claude (PDF).** Marketing PDF that mirrors the docs in linear form. Good for offline reading. <https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf>
7. **Anthropic — Equipping agents for the real world with Agent Skills (engineering blog).** Design rationale, real-world deployment patterns. <https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>
8. **Anthropic — Claude apps Skills launch announcement.** Product-level framing, plugin marketplace context. <https://claude.com/blog/skills>
9. **Agentic AI Foundation (AAIF).** Vendor-neutral [Linux Foundation](https://www.linuxfoundation.org/) initiative consolidating stewardship of open agent standards (skills, tools, protocols). Sits alongside the agentskills.io spec as the neutral home for cross-tool agent portability. Search "Agentic AI Foundation" for the current project page.
10. **Simon Scrapes — "The 1% way to use Claude Skills" (video).** Source of the six-step authoring frame summarised above; argues that 20–30 well-built curated skills beat 500 generic ones. <https://www.youtube.com/watch?v=6-D3fg3JUL4>

## In-repo references

- [`skills/skill-creator/SKILL.md`](../skills/skill-creator/SKILL.md) — full operating manual; load via prompt "create a skill", "audit a skill", etc.
- [`Instructions/copilot-authoring.instructions.md`](../com.github.copilot/rules/copilot-authoring.instructions.md) — schema and style rules for SKILL.md, agent, instruction, and prompt files. Auto-loaded when editing any of them.
- [`skills/sampler-framework/`](../skills/sampler-framework/), [`skills/automatedlab-deployment/`](../skills/automatedlab-deployment/), [`skills/datum-configuration/`](../skills/datum-configuration/) — worked examples of the SKILL.md-as-navigation-map + `references/` pattern after Pass-B split (May 2026).

## Choose the smallest suitable implementation

| Pick | When | Verification |
|---|---|---|
| Hook | An event must trigger a deterministic check independent of the model | Payload, timeout, exit-code, and bypass regression tests |
| Instruction | A path-scoped coding convention needs model judgment | Frontmatter, scope checks, and representative behavior checks |
| Skill | A reusable, on-demand workflow has a bounded outcome | Trigger and capability evals, including near-miss cases |
| Custom agent | The work needs a distinct role or capability boundary | Tool and delegation contracts plus behavioral evals |
| Prompt | A user-invoked VS Code entry point reuses an existing workflow | Frontmatter and invocation checks; no silent tool expansion |
| PowerShell function or script | A local deterministic operation needs structured input and output | Pester, parsing, static analysis, and `-WhatIf` for writes |
| MCP tool | A repeated cross-client integration needs a structured tool interface | Schema, authorization, failure, and integration tests |

An Instruction is guidance, not deterministic enforcement. Keep unconditional
checks in hooks or executable code. Prefer an existing module function over
another service for a one-shot local action. Use a narrow direct API call within
an existing workflow when a persistent MCP server adds no benefit; repository
MCP server curation remains out of scope.

Extend a suitable existing Customization before adding a new one. Preserve
capability boundaries: a Skill cannot grant tools, and a Prompt must not
silently widen its Custom agent's permissions. A new dependency needs an
explicit operational benefit, not just a convenient example to copy.

## Promote observed patterns deliberately

Keep a candidate in the task's existing project-scoped Memory Bank record,
separate from shipped Customizations. Capture one trigger and action, the
observed outcome, an evidence locator, counterexamples, and its intended scope.
Repeated observations are evidence; user silence is not approval, and an
invented numerical confidence is not a measurement.

Before promotion, reproduce the useful behavior, test a near-miss case, resolve
contradictory evidence, and obtain acceptance of the wider scope. Route the
accepted pattern through the table above and the existing `skill-creator` and
`agent-evals` workflows. Private transcripts and unreviewed generated guidance
do not enter the distributed catalogue. No observer daemon or automatic
project-to-global promotion is needed.

## Keep context changes deliberate

Use the existing Session handoff and compaction checkpoint at a completed task
boundary, preserving pending work, file paths, and validation evidence first.
Do not compact in the middle of an unresolved implementation step just because
a tool-call count crossed a threshold. Billing totals are not live context
occupancy; use client-reported context telemetry when available, and otherwise
report that the measurement is unavailable.
