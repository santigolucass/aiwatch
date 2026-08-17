# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - Unreleased

Initial release. Claude Code only.

### Added

- `aiwatch list` — recent sessions, sorted by last activity, with
  `--since`/`--all` and `--json`. Shows each session's AI-generated name
  (the same title `claude --resume`'s picker shows), read straight from
  the log.
- `aiwatch daily` — tokens and cost aggregated per local calendar day.
- `aiwatch show <id>` — per-model breakdown for one session, resolved by a
  git-style unique id prefix.
- `aiwatch live` — a full-screen operations panel for active
  Claude Code sessions: a 13-column session table (PID, status, context
  occupancy, git branch, cost, CPU%/MEM%, a CPU sparkline) grouped by
  agent kind, a sidebar with process/token/context-window detail for the
  selected session, and a scrolling per-session event log narrating tool
  calls and replies. Navigate with the arrows/`hjkl`; `x`/`X` kill/force-
  kill the selected session (matched by project directory, not wherever
  the agent last `cd`'d to — Linux only) after a confirm, `K` kills every
  visible session but requires typing "yes"; `p` pins, `A` purges dead
  entries, `s` cycles sort, `/` filters, `F` searches, `o` copies a
  `claude --resume` command, `E` exports to JSON/CSV, `T` cycles themes,
  `r` refreshes on demand; `W`/`H`/`C` switch to Timeline/History/Heatmap
  views, `?` shows the full key reference. `--ascii`, `--no-altscreen`,
  `--no-proc` (required on non-Linux), and `--snapshot` (render one frame
  and exit) round out the flags.
- Cost estimation via a `PricingTable` that fetches LiteLLM's pricing data,
  caches it locally for 24h, and falls back to a bundled snapshot when
  offline — with cache-creation tokens billed at their correct 1h/5m TTL
  rate rather than a single flat rate.
- Zero runtime dependencies (Ruby stdlib only).
