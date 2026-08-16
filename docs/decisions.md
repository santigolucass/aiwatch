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

## Unknown model handling

A model absent from the pricing table renders cost as `?` with a warning
surfaced to the user — never a silent `$0.00`, which would be
indistinguishable from "genuinely free."
