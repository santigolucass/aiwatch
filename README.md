# aiwatch

[![CI](https://github.com/santigolucass/aiwatch/actions/workflows/ci.yml/badge.svg)](https://github.com/santigolucass/aiwatch/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D)
![Zero runtime dependencies](https://img.shields.io/badge/dependencies-zero-brightgreen)

**An `htop` for your local AI coding agents.** It reads the session
logs [Claude Code](https://claude.com/product/claude-code) already keeps on
your machine and turns them into token usage, estimated cost, process
stats, and a live event feed — per session, per day, or as a full-screen
dashboard while agents are running. Nothing leaves your machine.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                         AIWATCH — AI Agent Terminal Operations Panel                           │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
● 1 active   ○ 1 dead   |   Cost: $0.3270   |   17:00:58
Tokens  In: 4   Out: 21,800   Cache: 218,000
Sessions: 1 active  1 dead  2 total   |   Avg tokens/turn: 109,002
┌─ Claude Code (2) ───────────────────────────────────────────────────────┐
│    PID STATUS   CTX TITLE          COST  CPU%  MEM% STAR… BRANCH MODEL  │
│> 84213 ACTIVE   86% Fix flaky…   $0.28…     -     - 1m    main   claud… │
│      - DEAD     23% Rewrite t…   $0.04…     -     - 10m   -      claud… │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
┌─ Session Log: /home/dev/code/myapp ─────────────────────────────────────────────────────────┐
│19:59:28 ● TOOL      Executed 1 tool: [Bash]                                                  │
│19:59:58 ● TOOL      Executed 1 tool: [Edit]                                                  │
│20:00:28 ● ASSISTANT Ran the flaky spec 20x locally; it was a timing race, not the fixture.    │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
KEYS: hjkl Nav  x Kill  X Force  A Purge  K All  p Pin  s Sort  / Filter  F Search  r Refresh  …
```

**Status:** v0.1.0, Claude Code only. Not yet published to RubyGems — see
[Install](#install) to run it from source. Other agents (Codex CLI, Gemini
CLI) are on the roadmap behind the same adapter interface that already
powers Claude Code support.

## Contents

- [Why](#why)
- [Install](#install)
- [Usage](#usage) — [`list`](#aiwatch-list-or-just-aiwatch) ·
  [`daily`](#aiwatch-daily) · [`show`](#aiwatch-show-id) ·
  [`live`](#aiwatch-live) · [`--json`](#--json)
- [How it works](#how-it-works)
- [Development](#development)
- [Roadmap](#roadmap)
- [License](#license)

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
SESSION   NAME                         PROJECT                   MODEL(S)                  INPUT  OUTPUT  CACHE R/W  COST (USD)  LAST ACTIVITY
b3f1a7c2  Fix flaky checkout test      /home/dev/code/myapp      claude-sonnet-5,claude-…    195   16.7K  1.6M/1.4M     $6.3180  5h ago
e9c4d8a1  Rewrite the onboarding docs  /home/dev/code/docs-site  claude-sonnet-5              60    3.1K   90K/200K     $0.5491  2d ago
```

`NAME` is the same AI-generated title `claude --resume`'s picker shows —
read from the session log, not computed by aiwatch — and renders as `?`
for a session too new to have one yet. A session's id is shown in green
(on a TTY) when its log file was modified in the last 5 minutes — i.e.
it's active (configurable with `--active-minutes`).

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
Name:     Fix flaky checkout test
Project:  /home/dev/code/myapp
Activity: 6h ago -> 5h ago
Cost:     $6.3180

MODEL            INPUT  OUTPUT  CACHE READ  CACHE CREATE  COST (USD)
claude-sonnet-5    165   14.5K        1.4M          1.2M     $5.2253
claude-opus-5       30    2.2K        200K          150K     $1.0926
```

An ambiguous prefix lists the matching session ids instead of guessing.

### `aiwatch live`

A full-screen, auto-refreshing operations panel for your active Claude
Code sessions — process stats, not just a token/cost table. Every session's
row carries its OS process (PID, CPU%, MEM%, a CPU sparkline), its real
git branch, and a live context-window occupancy estimate; the selected
session expands into a sidebar (process detail, token/cost totals, a
context-window bar) and a scrolling log of what it's actually doing
right now (tool calls, assistant replies, user prompts):

```
┌────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                AIWATCH — AI Agent Terminal Operations Panel                      │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
● 1 active   ○ 1 dead   |   Cost: $0.3270   |   17:01:24
Tokens  In: 4   Out: 21,800   Cache: 218,000
Sessions: 1 active  1 dead  2 total   |   Avg tokens/turn: 109,002
┌─ Claude Code (2) ─────────────────────────────────────────────────┐┌─ Session Detail ──────────────┐
│     PID STATUS   CTX TITLE        COST  CPU%  MEM% STAR… BRANCH … ││PID:        84213              │
│>  84213 ACTIVE   86% Fix flaky… $0.28…     -     - 1m    main   … ││Status:     ACTIVE             │
│       - DEAD     23% Rewrite t… $0.04…     -     - 10m   -      … ││Model:      claude-sonnet-5    │
│                                                                    ││Branch:     main               │
│                                                                    ││Started:    1m ago             │
│                                                                    ││CPU: -   MEM: -   Stop: -       │
└─────────────────────────────────────────────────────────────────────┘└────────────────────────────────┘
┌─ Session Log: /home/dev/code/myapp ───────────────────────────────────────────────────────────┐
│19:59:54 ● TOOL      Executed 1 tool: [Bash]                                                    │
│20:00:24 ● TOOL      Executed 1 tool: [Edit]                                                    │
│20:00:54 ● ASSISTANT Ran the flaky spec 20x locally; it was a timing race, not the fixture.      │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
KEYS: hjkl Nav  x Kill  X Force  A Purge  K All  p Pin  s Sort  / Filter  F Search  r Refresh  o Open  G Group  L Log  W Timeline…
```

Every one of these keys acts instantly, no Enter needed, except where
noted:

| Key | Does |
|---|---|
| `↑`/`↓`/`j`/`k`, `←`/`→`/`h`/`l` | Move the selection |
| `Home`/`End` | Jump to the first/last visible session |
| `PgUp`/`PgDn` | Scroll the session log |
| `x` | Kill the selected session (`SIGTERM`), after a `y`/`n` confirm |
| `X` | Force-kill (`SIGKILL`), same confirm |
| `K` | Kill **every** visible active session — requires typing `yes` and Enter, not a single keypress, since this is a much bigger blast radius than `x`/`X` |
| `A` | Purge dead entries from the table |
| `p` | Pin/unpin the selected session to the top |
| `s` | Cycle sort: last activity → cost → started → name |
| `G` | Toggle grouping |
| `/` | Filter sessions by title/project/branch (type, Enter to apply, Esc to cancel) |
| `F` | Search and jump to the next match (same text-entry flow as `/`) |
| `r` | Refresh immediately, without waiting for the interval |
| `o` | Copy `claude --resume <id>` to your clipboard (and show it in the footer) |
| `L` | Toggle the session log panel |
| `E` | Export the currently visible sessions to JSON or CSV (type a path ending in `.csv` for CSV, Enter accepts the suggested default) |
| `T` | Cycle color theme |
| `W` / `H` / `C` / `d` | Switch to Timeline / History / Heatmap / back to the main Dash view |
| `?` | Show the full key reference |
| `q`, Ctrl-C | Quit |

**Process stats** (PID, CPU%, MEM%, STATUS) come from `/proc` — no
`lsof`, no gem, Linux only; use `--no-proc` to disable this entirely
(required on non-Linux, where every session then shows as DEAD since
there's no way to confirm a live process). A session with recent log
activity but no matching live process reads as **DEAD**, not gone — it
stays in the table (purge it with `A`) in case the process is just
between restarts. CPU%/MEM% need two samples to compute a rate, so a
freshly-discovered process's first frame shows `-` until the next tick.

**Branch** is read straight from `.git/HEAD` on the live process's
actual current working directory (following worktree indirection), not
from the session log — the log's own `gitBranch` field is pinned to
wherever the session launched and can't be trusted once an agent `cd`s
into a git worktree.

**Context window** shows the most recent turn's occupancy against the
model's *real* context limit (from the same pricing data aiwatch already
uses for cost — never a hardcoded 200k guess, which would be actively
wrong for a 1M-context model).

Killing a process works by matching a running `claude` process's real
cwd against the session's project directory (not wherever the agent's
tool calls later `cd`'d to) — Linux only, and refuses to guess if more
than one process matches.

```
Options:
  --active-minutes N    Minutes of inactivity before a session drops out of live (default: 5)
  --refresh SECONDS     Refresh interval in seconds (default: 2)
  --ascii               Plain ASCII glyphs instead of Unicode box-drawing/Braille
  --no-altscreen        Don't switch to the terminal's alternate screen buffer
  --no-proc             Skip /proc scanning entirely; required on non-Linux
  --snapshot            Render a single frame to stdout and exit
```

### `--json`

`list`, `daily`, and `show` all accept `--json`. This is the contract; it
won't change shape without a version bump.

`list` emits an array of:

```json
{
  "session_id": "b3f1a7c2-4e6d-4a9b-8f21-7d5c9e2a11f0",
  "name": "Fix flaky checkout test",
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

`name` is `null` for a session too new to have an AI-generated title yet.

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
specifically to make this cheap later: Codex CLI and Gemini CLI adapters,
sitting alongside Claude Code in the same `live` dashboard rather than a
separate tool per agent. Budgets/alerts are also on the list.

## License

MIT — see [LICENSE](LICENSE).
