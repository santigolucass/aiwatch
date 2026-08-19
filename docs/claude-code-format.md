# Claude Code session log format (observed)

This documents the schema `aiwatch` actually parses, based on inspecting real
session files on a live machine (28 files, 12,120 assistant usage events)
before writing the parser. Claude Code does not publish this format, and it
has changed across versions before — treat this as a snapshot, not a spec.

## Location

```
~/.claude/projects/<project-slug>/<session-uuid>.jsonl
```

One file per session, one JSON object per line. Files can reach tens of MB,
so the parser streams line-by-line rather than loading a whole file.

## Line types

Each line has a `type` field. Observed values include `assistant`, `user`,
`system`, `mode`, `permission-mode`, `ai-title`, `file-history-snapshot`,
`file-history-delta`, `bridge-session`, `pr-link`, `queue-operation`, and
others. **Only `type: "assistant"` lines carry token usage.** `ai-title`
lines carry the human-readable session name shown in `claude --resume`'s
picker (see below); every other type is irrelevant to aiwatch and is
skipped.

### `ai-title` line shape

```jsonc
{"type": "ai-title", "aiTitle": "Fix the login bug", "sessionId": "4244444b-..."}
```

Repeated many times per session with the same value (like the streamed
`assistant` duplicates), but can also appear more than once with a
*different* `aiTitle` — Claude Code regenerates it as the session
progresses. Since the file is append-only, the last one encountered
while reading top-to-bottom is the most recent, and is what aiwatch
keeps (`Session#set_title`). A session with no `ai-title` line at all
(e.g. too short for one to have been generated) has `Session#title ==
nil`.

## Assistant line shape (fields aiwatch reads)

```jsonc
{
  "type": "assistant",
  "timestamp": "2026-07-31T09:45:59.650Z",   // ISO 8601, UTC
  "cwd": "/home/lucas/code/fluxo",            // project working directory
  "sessionId": "4244444b-...",                // matches the filename
  "message": {
    "id": "msg_011CdZvQxN995YdH4o7KCMBN",     // dedup key
    "model": "claude-sonnet-5",
    "usage": {
      "input_tokens": 2,
      "output_tokens": 452,
      "cache_creation_input_tokens": 26281,
      "cache_read_input_tokens": 35132,
      "cache_creation": {
        "ephemeral_1h_input_tokens": 26281,
        "ephemeral_5m_input_tokens": 0
      }
    }
  }
}
```

Fields present but **not** used by aiwatch: `requestId`, `uuid`,
`parentUuid`, `session_id` (a duplicate of `sessionId`), `effort`,
`version`, `gitBranch`, `entrypoint`, `stop_reason`, message `content`
(including `thinking` blocks — never logged or displayed by aiwatch).

## Parsing rules and why

1. **Only `type: "assistant"` with a Hash `message.usage`.** Every other
   line type is irrelevant to cost and is skipped without a warning.

2. **Dedup by `message.id`.** The same message is written to the file more
   than once — once per streamed content block (thinking / tool_use / text)
   — but every duplicate carries the identical, already-final `usage`
   object, not a growing partial. Deduping means "keep the first occurrence,
   discard the rest," not "sum them." Across a sample corpus, no
   `message.id` was ever observed in more than one session file, so
   per-file (per-session) dedup is equivalent to global dedup and is what
   aiwatch does — it's cheaper and keeps usage correctly scoped to its
   session even in the (unobserved) case of an id collision across files.

3. **`model: "<synthetic>"` is skipped silently.** These are local
   placeholder messages with no billable usage — not an unknown model
   worth warning about.

4. **Cache creation splits into two billing tiers.** `usage.cache_creation`
   breaks `cache_creation_input_tokens` into `ephemeral_1h_input_tokens` and
   `ephemeral_5m_input_tokens`, which LiteLLM prices at different per-token
   rates (`cache_creation_input_token_cost_above_1hr` vs
   `cache_creation_input_token_cost`). In the sample corpus, **100% of
   cache creation was 1h-TTL**, and using a single flat rate for all cache
   creation understated total cost by 16% overall (and ~60% on the cache
   creation component alone). If the breakdown is missing, or
   `ephemeral_1h + ephemeral_5m != cache_creation_input_tokens` (seen once
   in 6,277 events, cause unknown), aiwatch falls back to treating the
   full total as 5m-tier — the cheaper, more conservative assumption.

5. **Project name comes from `cwd`, not the directory slug.** The slug in
   the file path (e.g.
   `-home-lucas-code-fluxo--claude-worktrees-feat-kan-85-mobile-foundation`)
   collapses `/`, `.`, and `+` all to `-` and cannot be reversed
   unambiguously. `cwd` on each event gives the exact path directly. A
   session's project is taken as the most frequent `cwd` across its events,
   as a defensive tie-breaker in case it ever varies within one file.

## What a "session" is

The file's UUID (its name) is the session id. A session is "active" if its
file's mtime is within the configured threshold (default 5 minutes) of now.

## Subagent transcripts

A subagent spawned via the `Agent` tool gets its own transcript, nested
under whichever session launched it:

```
~/.claude/projects/<project-slug>/<parent-session-uuid>/subagents/agent-<hex-id>.jsonl
~/.claude/projects/<project-slug>/<parent-session-uuid>/subagents/agent-<hex-id>.meta.json
```

The `.jsonl` file is the same shape as a top-level session (`assistant`/
`user` lines, same `usage` fields) — `aiwatch` reads it through the
identical parsing path, so a subagent gets real cost/token accounting
rather than the "no usage, unattributed" gap this doc used to note here.

The sibling `.meta.json` gives everything the `.jsonl` alone doesn't:

```jsonc
{
  "agentType": "general-purpose",
  "description": "Implementar KAN-156 credenciais Órulo",
  "toolUseId": "toolu_...",
  "parentAgentId": "a1a0e84cc969e55b4",   // present only if spawned by another subagent
  "spawnDepth": 2
}
```

`description` becomes the subagent's row title in `live` (no
description → falls back to `?`, same convention as everywhere else).
`parentAgentId`, when present, means this subagent's parent is *another
subagent*, not the top-level session directly — real nesting more than
one level deep, confirmed in a corpus sample (170 of 339 subagent files
had a `parentAgentId`). When absent, the parent is the top-level session
whose uuid appears in the path (two directories up from the `.jsonl`).
Reading `.meta.json` has no backfill dependency, unlike deriving the
description from the parent session's own `toolUseResult` lines (tried
first, rejected — see `docs/decisions.md`).

## Known gaps

- `usage.iterations` (an array, seen with exactly one entry per event in
  the corpus) is not consumed. If Claude Code ever emits multiple
  iterations per line for agentic/tool loops, usage may need to be summed
  from `iterations` instead of the top-level fields.

## Fields the `live` dashboard reads (beyond cost math)

`FeedBuilder` (the live dashboard's per-session event feed and sidebar
side-channels — see `docs/decisions.md`) reads more of the schema than
the cost path above. Same caveat as everywhere else in this doc: this is
a snapshot of one real corpus, not a published spec, and every access is
nil-safe for exactly that reason.

- **`message.content`** (assistant lines): in the inspected corpus (CLI
  v2.1.233), each line's `content` array holds exactly one block; the
  same logical message streams across multiple lines sharing one
  `message.id`. Block `type` observed: `text` (`{text}`), `thinking`
  (`{thinking, signature}` — often empty, never narrated), `tool_use`
  (`{id, name, input}` — `name` is `mcp__<server>__<tool>` for MCP
  tools, shortened to `<tool>` in the feed).
- **`message.stop_reason`**: `tool_use`, `end_turn`, `stop_sequence`, or
  `null` (a non-final streaming chunk). No `max_tokens`/`refusal`
  observed.
- **`effort`**: top-level on the assistant line, not inside `message`.
  Only ever `"high"` in the inspected corpus, but the field exists.
- **`message.diagnostics.cache_miss_reason`**: present on a small
  fraction of assistant lines (`previous_message_not_found`,
  `tools_changed`, `model_changed`); tracked as a count, not narrated.
- **`user` lines**: `message.content` is a bare `String` (a real prompt)
  or an `Array` of `tool_result` blocks (`{type, tool_use_id, content,
  is_error}`). Only `is_error` is read — full tool output is
  intentionally not surfaced in the feed.
- **`system` lines**, by `subtype`: `turn_duration`
  (`{durationMs, messageCount, ...}`, top-level on the line) and
  `compact_boundary` (`{compactMetadata: {trigger, preTokens,
  postTokens, ...}}`) are read; other subtypes
  (`away_summary`, `local_command`, `bridge_status`,
  `scheduled_task_fire`) are not.
- **`pr-link` lines**: `{prNumber, prUrl, timestamp}`.
- **`permission-mode` lines / the `permissionMode` field**: real
  variance observed (`bypassPermissions`, `auto`, `acceptEdits`, `plan`,
  `default`) — tracked as a side-channel, not narrated in the feed.
- **`version`**: constant within a session; used for a per-session
  display field.
- **Deliberately not read**, despite being present: `mode`/`entrypoint`
  (zero variance observed — always `"normal"`/`"cli"`), `last-prompt`
  and `custom-title` (redundant with `ai-title` for this project's
  purposes), `worktree-state`/`relocated` (branch comes from a live
  `.git/HEAD` read instead — see `docs/decisions.md`), `queue-operation`,
  `file-history-*`, `bridge-session`, `agent-name`.

`gitBranch` (present on most message-bearing lines) is read by nothing
in this codebase — deliberately: it's pinned to the session's launch
directory and reports `"HEAD"` whenever that directory isn't a git repo,
even after the session's real cwd moves into one. See "Distrust the
logged `gitBranch`" in `docs/decisions.md`.
