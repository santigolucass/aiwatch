# frozen_string_literal: true

module Aiwatch
  # Turns the most recent assistant turn's token components into the
  # sidebar's stacked context-window bar. Pure math — no I/O, no model
  # knowledge beyond whatever `limit` it's handed.
  #
  # The limit MUST come from real pricing data (PricingTable#context_limit_for),
  # never a hardcoded assumption: on a real corpus, 70-80% of turns on
  # this project's own 1M-context models exceed the commonly-assumed
  # 200k-token window (see docs/decisions.md) — a wrong denominator would
  # render most sessions as over 100% full.
  module ContextWindow
    Breakdown = Struct.new(:input_pct, :cache_write_pct, :cache_read_pct, :output_pct, :free_pct, :occupied, :limit)

    module_function

    # Returns a Breakdown, or nil when `limit` is unknown (an unpriced or
    # unrecognized model) — callers must render "?" rather than assume a
    # default limit.
    def breakdown(input:, cache_write:, cache_read:, output:, limit:)
      return nil unless limit&.positive?

      to_pct = ->(n) { 100.0 * n.to_i / limit }
      input_pct = to_pct.call(input)
      cache_write_pct = to_pct.call(cache_write)
      cache_read_pct = to_pct.call(cache_read)
      output_pct = to_pct.call(output)
      free_pct = [100.0 - input_pct - cache_write_pct - cache_read_pct - output_pct, 0.0].max
      occupied = input.to_i + cache_write.to_i + cache_read.to_i + output.to_i

      Breakdown.new(input_pct, cache_write_pct, cache_read_pct, output_pct, free_pct, occupied, limit)
    end
  end
end
