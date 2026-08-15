# frozen_string_literal: true

module Aiwatch
  module Renderers
    # Renders a numeric series as a single-row Braille sparkline. Each
    # character packs 2 samples (one per sub-column), each independently
    # quantized to 4 vertical levels and filled bottom-up, like a compact
    # bar chart. Braille (U+2800-28FF) is Unicode East-Asian-Width
    # "Neutral" — unlike the "Ambiguous" glyphs that caused a real
    # alignment bug in this project (see docs/decisions.md) — so it
    # renders as a single terminal column everywhere, which is exactly why
    # tools like ttyplot use it for this.
    module BrailleSparkline
      BLANK = 0x2800
      # Bottom-up dot bits, one column each: level 1 lights only the
      # bottom dot, level 4 lights the whole column.
      LEFT_LEVELS = [0x40, 0x04, 0x02, 0x01].freeze
      RIGHT_LEVELS = [0x80, 0x20, 0x10, 0x08].freeze

      module_function

      # values: numeric series, oldest first. Self-normalizes to its own
      # max (0 or all-blank/negative series render as a flat blank line).
      # width: number of Braille characters to emit (each holds 2 samples).
      def render(values, width:)
        samples = last_n_padded(values, width * 2)
        max = samples.map { |v| v.to_f }.max
        max = 1.0 if max.nil? || max <= 0

        samples.each_slice(2).map { |left, right|
          bits = fill_bits(left, max, LEFT_LEVELS) | fill_bits(right, max, RIGHT_LEVELS)
          (BLANK + bits).chr(Encoding::UTF_8)
        }.join
      end

      def last_n_padded(values, n)
        tail = values.last(n)
        tail = ([0] * (n - tail.length)) + tail if tail.length < n
        tail
      end
      private_class_method :last_n_padded

      def fill_bits(value, max, levels)
        return 0 if value.nil? || value <= 0

        level = [(value / max * levels.length).ceil, levels.length].min
        levels.first(level).sum
      end
      private_class_method :fill_bits
    end
  end
end
