# Decisions log

Product/implementation ambiguities resolved in favor of the simplest option,
recorded here instead of blocking on them.

## Gem name: `aiwatch`

Chosen over `agentop` and `llm_meter`; all three were available on
RubyGems (`gem search` returns nothing, `rubygems.org/api/v1/gems/<name>.json`
returns 404) at the time of writing.

## Dedup scope: per-session file, not global

See `docs/claude-code-format.md` rule 2. No `message.id` was observed
repeated across files in a sample corpus, so per-file dedup is equivalent
to global dedup, cheaper, and keeps a stray future collision correctly
scoped to its own session rather than silently dropping it from whichever
session happened to be parsed second.

## Cache-creation TTL fallback: assume the cheaper 5m tier

When `usage.cache_creation`'s 1h/5m breakdown is missing or doesn't sum to
`cache_creation_input_tokens`, aiwatch treats the whole amount as 5m-tier
(the lower per-token rate) rather than 1h-tier. Cost estimates should never
overstate what a user was charged when the source data is ambiguous.

## Project identity: most frequent `cwd`, not the directory slug

See `docs/claude-code-format.md` rule 5. The slug is lossy; `cwd` is exact.
Using "most frequent" rather than "first" or "last" is a defensive
tie-breaker for the (unobserved) case of a `cwd` changing mid-session.

## GitHub username

The gemspec homepage and README clone URL use `santigolucass`, verified
via `gh api user` — not guessed from the commit author or email.

## `standard` not run locally

`standard`'s dependency `prism` needs to compile a native extension, which
needs `ruby-dev` headers not installed on this machine (and no passwordless
sudo to install them). `rake test` runs clean locally; `rake standard`
(and the `standard` CI job) is unverified until CI actually runs it. Worth
checking on the first CI run rather than assuming it's clean.

## Dropped the `●` active marker; color the session id instead

The original `list`/`live` tables used a leading `●` column to mark active
sessions. In a real terminal this misaligned every column after it,
because `●` (U+25CF, Unicode East-Asian-Width category "Ambiguous") some
terminals render as double-width while Ruby's `String#length` — and this
project's column-width math — counts it as one character. The fix isn't a
width-detection hack; it's dropping the glyph: active sessions are now
shown by coloring the SESSION id itself (bold green), so there's no
separate variable-width cell to misalign in the first place. Confirmed
this was the actual cause (not a math bug) by checking the ANSI-stripping
width calculation in isolation before touching the design.

## `live`'s sparkline uses Braille, not block characters

For the per-session token-throughput sparkline in `live`, Braille
(U+2800–28FF) was chosen over the more common `▁▂▃▅▇█` block-element
sparkline glyphs specifically because those blocks are *also* categorized
"Ambiguous" width — the same category that caused the marker bug above.
Braille is "Neutral," which in practice renders as one column reliably
across terminals; it's why tools like `ttyplot` use it for exactly this.
Each sparkline is self-normalized to its own session's max value (not a
shared scale across sessions), and shown in that session's own stable
color rather than overlaid with other sessions' lines in one shared plot
— avoiding the cell-level color collision that a true multi-series
overlaid chart would hit when two sessions' lines land in the same
character cell (a terminal can only give one foreground color per
character, not per sub-dot).

## `PROJECT` and `MODEL(S)` columns are capped and truncated

Both were unbounded — a real absolute project path or a multi-model
comma list can easily push a `list`/`live` row past 100+ visible columns,
which wraps in a normal-width terminal and, in a screenshot, looks
indistinguishable from broken column alignment (which is what this was
mistaken for after the `●`-marker fix, since that fix didn't touch
column width at all and the row was still just as wide). `TextTable.render`
now accepts `max_widths:`, and any cell over its column's cap is
truncated with a trailing "…". Not applied to any column that may carry
ANSI color codes (`SESSION`, `live`'s sparkline) — truncation is a plain
character-count operation and would cut mid-escape-sequence.

This bounds the row but doesn't make it adapt to the actual terminal
width; a very narrow terminal (well under 80 columns) can still wrap it,
especially in `live` where the sparkline alone is 20 columns wide.

## `live` writes `\r\n`, not a bare `\n`

The actual cause of the "still misaligned, nothing changed" report (after
both the `●`-marker fix and the column-width cap): `setup_terminal` puts
the tty into raw mode via `@in.raw!` before every render. Raw mode clears
`OPOST`/`ONLCR` on the *whole* tty device — stdin and stdout share one
device when connected to a real terminal, so this is not scoped to
input — which is exactly the automatic `\n` → `\r\n` translation a normal
terminal relies on. `puts`/`print "...\n"` then just moves the cursor
down a row without returning to column 0, so every line starts wherever
the previous one's cursor ended, cascading further right frame after
frame. This never showed up in testing because it only manifests once
raw mode is genuinely engaged on a real tty — a plain `StringIO`/pipe
target never exercises it, same class of gap as the color bug. Fixed by
writing `\r\n` explicitly for every line `live` draws instead of relying
on the terminal to translate it, which is also just what any full-screen
raw-mode CLI (vim, htop) has to do.

## Sparkline: a recorded zero is a low baseline dot, not blank space

`BrailleSparkline` originally rendered any non-positive value — a real
recorded tick with zero throughput, and a slot that hasn't been recorded
yet — identically, as the fully-blank Braille character (U+2800, no dots
raised). In practice a session is idle between generations far more
often than it's actively streaming tokens, so most of a `live` row's
sparkline was blank most of the time — visually indistinguishable from
"this column doesn't work," which is exactly what it looked like after
the `\r\n` fix stopped the layout from cascading and there was nothing
left to blame but the chart itself.

Fixed by distinguishing the two cases: a slot with no recorded sample yet
(new session, or history not filled in that far back) still renders
fully blank; a slot with a real recorded sample of 0 or less renders a
single low dot instead. `last_n_padded` now pads with `nil` rather than
`0` so the two are distinguishable at all — an idle *tracked* session now
reads as a flat line, matching the "flat = idle" description this
project already gives it, rather than as empty space.

## `live` is interactive: ↑/↓ select, x kills (with confirmation)

↑/↓ move a cursor between sessions; the selected one expands into a
detail panel above the table, reusing `Table#render_show` (the exact
same content as `aiwatch show <id>`) rather than a separate rendering
path. `x` always asks for confirmation (`y`/`n`/Esc) before acting —
killing an agent's process is irreversible and can land mid-task, so
this never fires on a single accidental keypress. The signal sent is
SIGTERM, not SIGKILL, to give the process a chance to react rather than
dying instantly.

The selection cursor is a plain ASCII `>`/` ` leading column, not a
Unicode glyph — same reasoning as dropping `●` for the active marker:
anything with ambiguous terminal width risks the exact column-alignment
bug this project already hit twice.

Selection tracks a session *id*, not a table row index, and is
re-synced after every refresh: if the selected session disappears
(inactivity, or it was just killed), selection falls back to the first
remaining session rather than pointing at whatever now occupies that row
index, which would silently select the wrong session.

## Killing a session's process: match by project directory, not by cwd

`aiwatch` only ever read `.jsonl` files before this; it had no notion of
*which OS process* was writing to one, and `ProcessFinder` went through
two wrong approaches before landing on a reliable one:

1. Scanning `/proc/*/fd` for whoever had the session's log file open.
   Wrong in practice, not just occasionally flaky: checked against real
   running `claude` processes, **none** had their `.jsonl` open at any
   given instant, because Claude Code writes it append-only (open,
   write, close) per event rather than holding the descriptor open.
2. Matching `/proc/PID/cwd` against `Session#project` (the session's
   *most frequent* cwd). Also wrong, and in a way real usage hits
   constantly: `project` drifts to wherever the agent's tool calls
   happened — a subdirectory, a git worktree — while the actual OS
   process never leaves wherever `claude` was launched. Checked against
   a real session where the agent spent 408 of 456 events inside a git
   worktree subdirectory: `Session#project` pointed at the worktree,
   the real process's `/proc/PID/cwd` was still the repo root, and the
   match failed every time.

What's actually stable: a session's log file lives under
`~/.claude/projects/<slug>/`, and that slug is derived from the launch
directory once, at session start — it never moves just because the
agent `cd`s around later. `ProcessFinder.find_pid` now takes the session
file path, reads its parent directory's name as the target slug, and
compares that against each candidate process's *own* cwd
(`/proc/PID/cwd`, kernel-maintained, independent of open files),
slugified the same way Claude Code names project directories
(`/` and `.` → `-`) — filtered to processes whose `/proc/PID/comm` is
`claude`. Verified against the same real worktree-heavy session: resolves
to the correct PID now.

This still avoids shelling out to `lsof` or adding a gem, so the
zero-runtime-dependency goal holds. Linux-only: `/proc` doesn't exist on
macOS, so `ProcessFinder.find_pid` returns `nil` there rather than
raising. It also returns `nil`, not a guess, when zero *or more than
one* process matches (e.g. two terminals launched from the same
directory) — sending a signal to the wrong process is worse than not
finding one. The one known residual gap: slugifying is many-to-one
(different real paths can theoretically collapse to the same slug), so
a match is not mathematically guaranteed correct — just true for every
real case checked so far, and far more reliable than the two prior
attempts.

## A killed session is suppressed locally, not re-derived from the file

`Session#active?` is based on the log file's mtime; sending a signal to
the process doesn't touch that file, so a killed session would otherwise
keep showing as active until the mtime naturally goes stale
(`active_threshold_minutes`, several minutes by default) — refreshing
after a kill wouldn't be enough on its own to make it disappear. `live`
tracks killed session ids for the life of the run and filters them out
of every subsequent refresh regardless of file mtime, and refreshes
immediately after a kill attempt so this takes effect on the very next
frame rather than waiting for the regular interval. `r` also refreshes
on demand, for the same reason a new session showing up shouldn't need
waiting out the interval either.

## Session names come from `ai-title` lines, last one wins

`claude --resume`'s picker shows a human-readable title per session
instead of a bare uuid; that title lives in the log as its own line type
(`{"type": "ai-title", "aiTitle": "...", "sessionId": "..."}`), not on
the `assistant` lines aiwatch already parsed. It's regenerated as the
session progresses — one real session had two distinct `aiTitle` values —
so `Session#set_title` unconditionally overwrites on every `ai-title`
line seen, and since the file is append-only (read top-to-bottom in
chronological order), the last one encountered is the most recent one,
with no separate ordering logic needed. A session with none yet renders
as `?`, the same convention as an unknown model's cost or a missing
project.

## Unknown model handling

A model absent from the pricing table renders cost as `?` with a warning
surfaced to the user — never a silent `$0.00`, which would be
indistinguishable from "genuinely free."
