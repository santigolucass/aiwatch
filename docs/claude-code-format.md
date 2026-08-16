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

## Known gaps

- Subagent / sidechain events (`isSidechain: true`) carried no `usage` in
  the inspected corpus, so their cost, if any, is not separately
  attributed. Revisit if that's ever observed to be false.
- `usage.iterations` (an array, seen with exactly one entry per event in
  the corpus) is not consumed. If Claude Code ever emits multiple
  iterations per line for agentic/tool loops, usage may need to be summed
  from `iterations` instead of the top-level fields.
