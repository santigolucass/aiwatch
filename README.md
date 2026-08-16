# aiwatch

An htop for your local AI coding agents. It reads the session logs that
[Claude Code](https://claude.com/product/claude-code) already keeps on your
machine and turns them into token usage and estimated cost — per session,
per day, or live as agents run.

**Status:** v0.1.0, Claude Code only. Not yet published to RubyGems — see
[Install](#install) to run it from source. Other agents (Codex CLI, Gemini
CLI) are on the roadmap behind the same adapter interface that already
powers Claude Code support.

## Why

Claude Code doesn't show you a running cost meter. The information is all
there in `~/.claude/projects/*/*.jsonl` — aiwatch just reads it, computes
cost against real per-token pricing, and gets out of the way. It never
sends your session data anywhere; the only network call it makes is an
occasional fetch of *public* pricing data (see [How it works](#how-it-works)).

## Install

```
gem install aiwatch
```

Not yet published — for now, run from source:

```
git clone https://github.com/santigolucass/aiwatch
cd aiwatch
bundle install
ruby -Ilib exe/aiwatch list
```

Requires Ruby >= 3.2. No runtime dependencies.

## Usage

### `aiwatch list` (or just `aiwatch`)

Recent sessions, sorted by last activity.

```
$ aiwatch list --all
SESSION   PROJECT                   MODEL(S)                       INPUT  OUTPUT  CACHE R/W  COST (USD)  LAST ACTIVITY
b3f1a7c2  /home/dev/code/myapp      claude-sonnet-5,claude-opus-5    195   16.7K  1.6M/1.4M     $6.9205  12h ago
e9c4d8a1  /home/dev/code/docs-site  claude-sonnet-5                   60    3.1K   90K/200K     $0.8491  2d ago
```

A session's id is shown in green (on a TTY) when its log file was modified
in the last 5 minutes — i.e. it's active (configurable with
`--active-minutes`).

```
Options:
  --since DURATION      Only sessions active within this window, e.g. 7d, 30d (default: 7d)
  --all                 Include sessions of any age
  --active-minutes N    Minutes of inactivity before a session is no longer "active" (default: 5)
  --dir DIR             Override the Claude Code logs directory
  --json                Emit JSON instead of a table
```

### `aiwatch daily`

Tokens and cost aggregated by local calendar day, across all sessions. A
session that runs past midnight contributes to both days.

```
$ aiwatch daily
DATE        SESSIONS  INPUT  OUTPUT  CACHE R/W  COST (USD)
2026-08-15         1    195   16.7K  1.6M/1.4M     $6.9205
2026-08-13         1     60    3.1K   90K/200K     $0.8491
```

### `aiwatch show <id>`

Per-model breakdown for one session. `<id>` can be a full uuid or a unique
prefix, like `git show`.

```
$ aiwatch show b3f1a7c2
Session:  b3f1a7c2-4e6d-4a9b-8f21-7d5c9e2a11f0
Project:  /home/dev/code/myapp
Activity: 6h ago -> 5h ago
Cost:     $6.9205

MODEL            INPUT  OUTPUT  CACHE READ  CACHE CREATE  COST (USD)
claude-sonnet-5    165   14.5K        1.4M          1.2M     $5.2653
claude-opus-5       30    2.2K        200K          150K     $1.6552
```

An ambiguous prefix lists the matching session ids instead of guessing.

### `aiwatch live`

Interactive, auto-refreshing view of currently active sessions (default:
every 2s) — an `htop` for your agents. `↑`/`↓` move a selection cursor
between sessions and expand a detail panel above the table for whichever
one is selected; `x` asks for confirmation, then sends `SIGTERM` to the
process behind that session; `r` refreshes on demand; `q` or Ctrl-C
quits. All of these act instantly, no Enter needed. Each session also
gets its own color (stable
for the life of the run, assigned in the order sessions first appear)
and a small sparkline of its recent token throughput — a low flat
baseline means idle, a filled one means it's actively working:

```
$ aiwatch live
aiwatch live — 19:08:57 — 2 active session(s)

Session:  b3f1a7c2-4e6d-4a9b-8f21-7d5c9e2a11f0
Project:  /home/dev/code/myapp
Activity: just now -> just now
Cost:     $0.2359

MODEL            INPUT  OUTPUT  CACHE READ  CACHE CREATE  COST (USD)
claude-sonnet-5    165     18K           0             0     $0.1807
claude-opus-5       30    2.2K           0             0     $0.0552

   SESSION   PROJECT                   MODEL(S)                  COST (USD)  TOKENS/s (80s)        LAST ACTIVITY
>  b3f1a7c2  /home/dev/code/myapp      claude-sonnet-5,claude-…     $0.2359  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣾⣷⣄  just now
   e9c4d8a1  /home/dev/code/docs-site  claude-sonnet-5              $0.0311  ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⣀  just now

↑/↓ select session   x kill selected session   r refresh   q quit
```

(`b3f1a7c2` — the selected row, marked `>` — and its sparkline render in
the same color; `e9c4d8a1` gets a different one. `PROJECT` and
`MODEL(S)` are truncated with `…` past a fixed width so a long path or a
multi-model list can't push the row wider than the terminal and wrap.
The selection cursor is a plain `>`, not a Unicode glyph, for the same
reason the sparkline uses Braille and not block characters — see below.)

Pressing `x` replaces the footer with a confirmation prompt
(`Kill session b3f1a7c2? y = confirm, n/Esc = cancel`) before anything
happens — killing an agent's process is irreversible and might land
mid-task, so it never fires on a single accidental keypress. Finding
*which* process to signal works by matching a running `claude` process's
current working directory (`/proc/PID/cwd`) against the session's
project, so this only works on Linux; on other platforms, or if more
than one process matches, `live` reports "could not find a running
process" instead of guessing. A killed session disappears from the list
on the next refresh — including the immediate one `live` triggers right
after the kill, so you don't have to wait or press `r` yourself.

The sparkline is self-normalized per session — it shows *that* session's
own recent trend, not an absolute scale comparable across sessions. It's
built from Braille characters rather than fancier Unicode blocks on
purpose: Braille is Unicode "Neutral" width and reliably renders as one
terminal column everywhere, unlike some symbols that render double-width
in certain terminals and silently break column alignment (an earlier
version of this view used `●` for an active marker and hit exactly that).
A session that's been tracked for at least one tick but has zero
throughput right now shows a low single-dot baseline rather than empty
space, so it reads as "flat" instead of "not working" — a slot with no
recorded sample yet (the session just showed up) stays truly blank.

```
Options:
  --active-minutes N    Minutes of inactivity before a session drops out of live (default: 5)
  --refresh SECONDS     Refresh interval in seconds (default: 2)
```

### `--json`

`list`, `daily`, and `show` all accept `--json`. This is the contract; it
won't change shape without a version bump.

`list` emits an array of:

```json
{
  "session_id": "b3f1a7c2-4e6d-4a9b-8f21-7d5c9e2a11f0",
  "project": "/home/dev/code/myapp",
  "models": ["claude-sonnet-5", "claude-opus-5"],
  "input_tokens": 195,
  "output_tokens": 16700,
  "cache_read_tokens": 1550000,
  "cache_creation_tokens": 1370000,
  "cost_usd": 6.92048,
  "fully_known": true,
  "first_activity": "2026-08-15T09:00:00Z",
  "last_activity": "2026-08-15T09:20:00Z",
  "active": true
}
```

`daily` emits an array of `{date, session_count, input_tokens,
output_tokens, cache_read_tokens, cache_creation_tokens, cost_usd,
fully_known}`.

`show` emits the same shape as one `list` row, except `models` is replaced
by an array of per-model breakdowns (`{model, input_tokens, output_tokens,
cache_read_tokens, cache_creation_tokens, cost_usd}`), plus an
`unknown_models` array.

`fully_known: false` (or a model's `cost_usd: null`) means at least one
model in that row had no pricing data — the total still sums whatever
*was* known; it never silently reports `0`.

## How it works

**Data source.** aiwatch reads `~/.claude/projects/<project>/<session-uuid>.jsonl`
directly — the same transcripts Claude Code already writes locally. Nothing
is sent anywhere. Only `type: "assistant"` lines carry token usage; a
message can appear more than once in the file (once per streamed content
block), so aiwatch dedupes by `message.id`, keeping the usage from the
first occurrence rather than summing duplicates. Full schema notes are in
[`docs/claude-code-format.md`](docs/claude-code-format.md).

**Cost formula.** For each model:

```
cost = input_tokens        × input_rate
     + output_tokens       × output_rate
     + cache_read_tokens   × cache_read_rate
     + cache_creation_1h   × cache_creation_1h_rate
     + cache_creation_5m   × cache_creation_5m_rate
```

The last two lines matter: Claude Code's cache creation is billed at two
different rates depending on TTL (1 hour vs 5 minutes), and a lot of tools
in this space price all cache creation at one flat rate. Against a real
corpus, that understated total cost by 16% — mostly because 1h-TTL cache
creation, when present, is meaningfully more expensive per token. aiwatch
bills each TTL tier separately, falling back to the cheaper 5-minute rate
only when the source data doesn't say which tier applies.

**Pricing data.** Rates come from
[LiteLLM's pricing table](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json),
in three layers: a local cache (`~/.cache/aiwatch/pricing.json`, refreshed
every 24h), a live fetch when that cache is stale or missing, and a small
snapshot bundled with the gem for when both the network and the cache are
unavailable. A model missing from all three layers prices as `?`
(`cost_usd: null` in JSON) — never a silent `$0.00`.

**Zero dependencies.** Everything above is built on the Ruby standard
library — `json`, `optparse`, `net/http`, `io/console`, `time`, `date`. No
gems to conflict with your project's own.

## Development

```
bundle install
rake test        # minitest
rake standard     # linter
```

Product/format decisions made along the way, and why, are logged in
[`docs/decisions.md`](docs/decisions.md).

## Roadmap

Not in v0.1, but the adapter interface (`Aiwatch::Adapters::Base`) exists
specifically to make these cheap later: Codex CLI and Gemini CLI adapters,
`--csv` export, budgets/alerts, and a multi-agent consolidated `live` view.

## License

MIT — see [LICENSE](LICENSE).
