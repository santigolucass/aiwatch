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

## Unknown model handling

A model absent from the pricing table renders cost as `?` with a warning
surfaced to the user — never a silent `$0.00`, which would be
indistinguishable from "genuinely free."
