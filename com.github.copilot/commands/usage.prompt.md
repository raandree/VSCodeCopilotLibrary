---
description: Report this project's Copilot token, API call, and model usage from the session store.
argument-hint: 'repository name, "all", or a trailing day count (default: current repository, all time)'
---

# Copilot usage report

Load the `copilot-usage-stats` Skill and follow it. Query the session store
with #tool:copilot_sessionStoreSql.

Resolve scope from the argument:

- Empty — the current workspace repository, all time.
- A repository name — that repository.
- `all` — every project, ranked by total input.
- A number — restrict to that many trailing days.

Report in this order:

1. One sentence answering the question that was asked.
2. Per-model table: sessions, API calls, total input, fresh input, cache read, output.
3. A split by `agent_name` when more than one surface appears.
4. AI credits and dollars per model, computed from the current published rates,
   with the plan's monthly allowance for context.
5. Only the caveats that apply: unsynced current session, unrecorded cache
   writes, unpriced models, folded repository spellings.

Never add `input_tokens` and `cache_read_tokens` — the first already contains
the second. Never present the `cost` column as money; it holds a legacy request
multiplier. Report no rows as no rows; never estimate a figure the store did
not return.
