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

## A killed session is detected as dead, not suppressed locally

Superseded by the full-screen dashboard (see below): `active?` (log file
mtime) now only decides whether a session is *tracked* at all; whether
it's shown as ACTIVE or DEAD is re-derived every tick from a live `/proc`
scan, matched against each session's project directory the same way
`ProcessFinder.find_pid` always has. Killing a process makes it
disappear from `/proc`, so the very next `/proc` re-scan (forced
immediately after a kill attempt, not waiting for the regular interval)
already shows it as DEAD without needing to separately remember "this id
was killed" — the old `@killed_ids` local-suppression hash this section
used to describe is gone; liveness is asked for fresh, not cached.

## `live` became a full-screen operations dashboard

The single-view table (`docs/decisions.md`'s entries above, up through
"Session names come from `ai-title` lines") was replaced with a
full-screen operations panel: a title bar, a stats bar, a 13-column
session table grouped by agent kind, a three-box sidebar (process
detail, tokens, a context-window bar), a scrolling per-session event
log, sort/filter/search/pin/purge/kill-all/export/theme, and four extra
full-screen views (Timeline, History, Heatmap, and a generated `?` help
overlay) — all still zero-dependency, still verified against this
project's own real `~/.claude/projects` corpus and real running `claude`
processes at every step, not just unit tests. The sections below record
what changed and why; entries above this point describe the original
single-view implementation and mostly still hold (the `\r\n` fix, the
Braille sparkline, project/model column truncation) except where a later
entry here explicitly supersedes one.

### A Canvas replaces string concatenation

Every rendering bug logged above — the `●` marker, the column caps, the
`\r\n` cascade — came from building frames by concatenating strings and
hoping they fit. `Tui::Canvas` is a `width x height` grid of cells that
writes clip against on contact, which makes "this line is too wide"
structurally impossible instead of merely tested for. It's backed by a
per-cell grid, not a list of row spans: an earlier span-based design
(keep a list of `{col, text}` writes per row, compose left-to-right) had
a real bug where a box's title, written *after* the top border, got
silently dropped as "overlapping" the border span instead of painting
over part of it. The per-cell model fixes this by construction — a later
write always overwrites exactly the columns it touches and nothing
else — and also needed a `post` field on each cell (not just `pre`) so a
write's own *trailing* SGR codes (a closing reset with no character
after it) attach to that write's own last cell rather than leaking onto
whatever a completely unrelated later write happens to place next door.

### `Tui::Grid` is TextTable's counterpart for a fixed-width dashboard, not a replacement for it

`TextTable` (list/daily/show) answers "how wide do these columns need to
be"; `Grid` (the dashboard's 13-column table) answers "given exactly N
columns to fill, which of these get to exist, and how wide is each" —
different enough contracts that merging them would make both worse.
Columns carry a `priority`; when there isn't room for all of them, the
least-essential (highest priority number) drops first, and 0-2 never
drop. When there's surplus width, **weighted** (free-text) columns like
TITLE and DIRECTORY get first claim on it, and weight-0 capped columns
(PID, COST, CPU%...) only mop up whatever's left — tried the reverse
order first, and it was wrong in a way real widths hit constantly: a
handful of small-max columns (PID wanting +2, STATUS +2, COST +3...)
ate the *entire* surplus before TITLE ever got a look at it, so TITLE
sat at its bare minimum width even in a 140-column terminal. Weighted
columns having small `max` deltas by design is exactly why growing them
last starves them but growing fixed columns last doesn't.

### Theme's 256-color escape codes were invalid until this rewrite caught it

`Tui::Theme#sgr` emitted `\e[<palette-index>m` for every ansi256-depth
role (`\e[208m` for an orange border) — not a valid SGR sequence at all;
the correct extended-color form is `\e[38;5;<index>m`. Every color test
up to this point ran at `depth: :none` or stripped ANSI before
asserting, so nothing caught it — it surfaced only when converting a
real colored snapshot to HTML for a demo and finding every span came out
uncolored. Fixed by branching on depth: `:ansi16` codes are bare SGR
parameters (30-37) and stay as `\e[<code>m`; `:ansi256` codes are
palette indices and now get `\e[38;5;<code>m` (or `\e[1;38;5;<code>m`
bold). A reminder that "renders as expected when I strip the codes to
test it" and "renders as expected in a real terminal" are different
claims — the pricing-table/process-finder/git-branch verification
discipline this project already had was never applied to what the
*escape codes themselves* actually said.

### The context-window bar's denominator comes from real pricing data

Naively assuming a 200k-token context window is actively wrong for this
project's own models: on this machine's real corpus, 70-80% of turns on
the 1M-context models exceed 200k tokens, which would render most
sessions as "over 100% full." `max_input_tokens` is a field LiteLLM's
pricing data already carries, and `PricingTable` already fetches and
caches that data for cost math — `PricingTable#context_limit_for(model)`
just reads the field that was already in hand, so no new heuristic or
data source was needed. `nil` (unpriced/unknown model) renders as `?`,
never a guessed default. The bundled offline pricing snapshot had to be
regenerated to carry this field too, since it predates this feature.

### Distrust the logged `gitBranch`; read `.git/HEAD` from the live process's cwd instead

The `gitBranch` field Claude Code logs on each JSONL line is pinned to
wherever the session *launched*, and reports the literal string `"HEAD"`
whenever that launch directory isn't a git repo — even while the
session's real, current cwd later moved into one. Verified on a real
session: `gitBranch: "HEAD"` on all 2154 lines, while 1875 of them had
`cwd: /home/lucas/code/aiwatch`, which is a real repo on `master`.
`GitBranch.for(dir)` instead reads `.git/HEAD` directly from a live
process's actual cwd (found via `ProcessFinder`) — unaffected by any of
that, and cheap enough to not matter: measured ~1ms per read,
page-cached. It follows the worktree `gitdir:` indirection (a worktree's
`.git` is a *file* pointing elsewhere) so worktree sessions report their
own branch, not the main checkout's. The logged field is kept only as a
fallback for a dead session with no live process to ask.

### SessionStore tails files incrementally instead of re-parsing them

`list`/`daily`/`show` re-parse a whole file every call, which is fine
for a one-shot command but would mean re-reading this project's own
~250MB/34-file `~/.claude/projects` corpus every 2-second tick.
`SessionStore` keeps a `TailReader` per file with a stat-based skip gate
(untouched mtime+size ⇒ zero bytes read, not even opened) and reads only
the bytes appended since the last read otherwise. Measured on the real
corpus: cold refresh in 48ms (not the 10-30s a full parse would take),
and a no-op tick in 0.6ms.

A file larger than 256KB gets **tail-seeked** on its first read —
skipping straight to its last 256KB rather than reading from byte 0 — so
the dashboard has something to show immediately instead of blocking on
a multi-megabyte parse the moment it discovers an existing session.
Cumulative totals for the skipped leading portion are then backfilled a
bounded chunk at a time (512KB/tick by default — a conservative 32KB
default technically also converges, just over many minutes instead of
under a second; measured against the real corpus), prioritizing
whichever session is currently selected; `LiveSession#totals_partial?`
is true and cost renders with a `~` prefix until backfill catches up. No
background thread: `JSON.parse` doesn't release the GVL, so a thread
would stutter the render loop anyway while adding real thread-safety
surface for no benefit.

Backfill reads *backward* in fixed-size byte chunks with no line-
boundary alignment, so a chunk boundary can and does land mid-line. The
naive fix (discard each chunk's leading fragment as "probably torn")
was tried and is wrong: it discards the *wrong* half of the split line
and drops it entirely, losing one full line of data per chunk boundary
crossed — confirmed on a real corpus by comparing incremental-backfill
totals against a full re-parse, off by exactly `chunks × tokens_per_line`.
The fix carries each chunk's leading fragment forward and prepends it to
the *next* (further-back) chunk read, reconstructing the exact line that
boundary split — verified byte-exact against a synthetic 500-line file
with a deliberately awkward chunk size, and confirmed to converge to
*exactly* the same totals as a full re-parse across every real session
in the corpus (0 mismatches across 34 sessions).

A rotation or truncation mid-run (detected via inode change or a
shrinking size) makes `TailReader` correctly restart from scratch on its
own — but that alone isn't enough: the `Session` and dedup hash a
`SessionStore` cursor built from what the reader served *before* the
rotation are now stale data from a file that, as far as that cursor is
concerned, no longer exists. The first version of this fix let
`TailReader` silently reset itself while `SessionStore` kept folding
fresh post-rotation content into the old stale `Session` and dedup
hash — which, worse, actively *suppressed* the new content whenever an
id happened to collide with the old file's (e.g. a message re-sent after
rotation looked like an already-seen duplicate). Fixed by having
`TailReader` expose a one-shot `#reset?` signal so `SessionStore` knows
to rebuild the `Session`/dedup-hash/`LiveSession` trio from scratch on
exactly the tick a rotation is detected.

### The event feed shows conversation content — a reversal of "never display it"

`FeedBuilder` reads `message.content` to narrate the session log (tool
calls, assistant text snippets, user prompts) — the one place in
aiwatch that does. This directly reverses the earlier stated policy that
`message.content` (including `thinking` blocks) is "never logged or
displayed by aiwatch." Made deliberately, not accidentally: the
dashboard's whole point is showing what a session is *doing right
now*, and a feed that can't say what happened isn't that. Everything
stays 100% local exactly as before — the difference is that this
content now reaches the screen (and an `E` export), not just token/cost
math. Text is snippeted to 240 characters; `thinking` blocks are never
narrated (usually empty in practice, and the least useful to show even
when not); tool results show ok/error, not full stdout.

### The feed is built in file order, never sorted by timestamp

Session log timestamps are not monotonic — 1648 non-monotonic
transitions found across the real corpus, including one line that
jumped forward three hours and then back on the very next line (looks
like a TZ-handling bug on some code path, cause unconfirmed). Sorting a
feed by timestamp would visibly scramble it. `FeedBuilder#ingest` is fed
lines in the order `SessionStore` reads them (which is always file
order, append-only), and every timestamp it keeps is for *display*
only, never for ordering.

### `K` (kill all) requires typing "yes", not a single keypress

Every other destructive action here (`x`, `X`) asks for one
confirmation keypress, appropriate for a single, clearly-selected
target. Killing *every visible active session* at once is a
different order of consequence, and a single accidental `y` — the same
key that confirms a routine single-session kill — is exactly the kind
of muscle-memory mistake this should be immune to. `K` opens the same
text-entry mode `/` (filter) and `E` (export) already use, requiring the
literal string "yes" plus Enter; anything else cancels with no effect.

### Canvas neutralizes embedded control characters, not just ANSI codes

Found from real usage, not a test: the session log showing real
conversation content (see "reversal" above) means row text now
sometimes comes from an actual multi-line prompt or tool-arg block —
and a literal embedded newline, written straight through to the
terminal, moves the *real* cursor down a row on its own. That's LF's
own terminal-level meaning, unrelated to the OPOST/ONLCR translation
the original `\r\n` fix (see above) addresses, so raw mode doesn't
suppress it. The visible symptom was two-fold and looked unrelated
until traced to one cause: garbage text (an XML-tagged command block)
bleeding into the footer and overwriting the `o Open` key label, and an
active session appearing to "vanish and come back" every 1-2 seconds.
The second symptom is a consequence of `Screen#flush` diffing by
default: a corrupted row leaks onto whatever's below it, and if that
row's content doesn't happen to change on the next tick, diffing skips
repainting it — so the corruption persists until some unrelated content
change eventually forces that row to repaint. Fixed by having
`Canvas#write` run every string through `Tui::Ansi.sanitize` (replacing
every C0 control byte except ESC, and DEL, with a space) before any
other processing — the same "make bad input structurally impossible to
mis-render" posture Canvas already had for width, extended to control
bytes.

### CSV export is hand-rolled, not `require "csv"`

`aiwatch` has stayed zero-runtime-dependency by only ever using
default-gem stdlib (`json`, `optparse`, `net/http`, `io/console`,
`time`, `date`). As of Ruby 3.4, `csv` is a *bundled* gem, not a default
one — assuming it's installed would quietly break that guarantee for
anyone whose Ruby doesn't happen to have it bundled or already
installed. `Exporter`'s CSV path hand-rolls the ~10 lines of RFC 4180
quoting this export actually needs (quote a cell containing a comma,
quote, or newline; double any embedded quotes) rather than pull in the
gem for that.

The same class of bug slipped through anyway, caught by CI rather than
this reasoning: `o`'s clipboard copy used `require "base64"` +
`Base64.strict_encode64`, and `base64` *also* became a bundled gem in
Ruby 3.4 — this project's own local dev Ruby is 3.2, where that
`require` still silently works, so nothing caught it locally. The real
CI matrix (3.2/3.3/3.4) did: a clean `LoadError` on 3.4 only. Fixed by
using `Array#pack("m0")` instead, which produces the identical
standard-base64 output as `Base64.strict_encode64` but is core Ruby
(`Array#pack`), not a library `require` at all — nothing to become a
bundled gem out from under it. Worth remembering next time a new stdlib
call gets added here: check whether it's a `require` for something Ruby
core already gives you unprompted.

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
