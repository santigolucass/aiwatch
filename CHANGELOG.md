# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - Unreleased

Initial release. Claude Code only.

### Added

- `aiwatch list` — recent sessions, sorted by last activity, with
  `--since`/`--all` and `--json`.
- `aiwatch daily` — tokens and cost aggregated per local calendar day.
- `aiwatch show <id>` — per-model breakdown for one session, resolved by a
  git-style unique id prefix.
- `aiwatch live` — interactive, auto-refreshing view of currently active
  sessions, each with its own stable color and a self-normalized Braille
  sparkline of its recent token throughput. `↑`/`↓` select a session and
  expand a detail panel above the table; `x` asks for confirmation, then
  sends `SIGTERM` to the process behind the selected session (matched by
  `/proc/PID/cwd` — Linux only); `r` refreshes on demand.
- Cost estimation via a `PricingTable` that fetches LiteLLM's pricing data,
  caches it locally for 24h, and falls back to a bundled snapshot when
  offline — with cache-creation tokens billed at their correct 1h/5m TTL
  rate rather than a single flat rate.
- Zero runtime dependencies (Ruby stdlib only).
