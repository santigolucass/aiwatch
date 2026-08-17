# frozen_string_literal: true

require_relative "ansi"

module Aiwatch
  module Tui
    # A fixed-total-width column engine, the dashboard's counterpart to
    # TextTable's "size to content" model. TextTable answers "how wide do
    # these columns need to be"; Grid answers "given exactly N columns to
    # fill, which of these get to exist, and how wide is each" — the two
    # have different enough contracts that merging them would make both
    # worse (see docs/decisions.md).
    #
    # Column priority controls what gets dropped first when there isn't
    # room for every column: 0-2 are never dropped, 3+ are dropped
    # widest-numbered-first until the row fits.
    class Grid
      Column = Struct.new(:key, :header, :min, :max, :weight, :align, :priority, :truncate_from, :width)

      DEFAULTS = {min: 1, max: nil, weight: 0, align: :left, priority: 5, truncate_from: :right, width: nil, header: ""}.freeze

      def initialize(columns, gap: 1)
        @columns = columns.map { |c| Column.new(**DEFAULTS.merge(c)) }
        @gap = gap
      end

      # Returns Array<Column>, each with a concrete #width filled in, that
      # fit within available_width (including inter-column gaps).
      def layout(available_width)
        cols = @columns.map { |c| c.dup.tap { |dup| dup.width = c.width || c.min || 0 } }
        cols = drop_until_fits(cols, available_width)
        distribute_surplus(cols, available_width)
        cols
      end

      def render_header(cols, theme:)
        cols.map { |c|
          header = c.header.to_s
          header = Ansi.truncate(header, c.width) if Ansi.visible_length(header) > c.width
          pad(header, c.width, c.align)
        }.join(" " * @gap).then { |line| theme.paint(line, :header, bold: true) }
      end

      def render_row(cols, values, cell_for: nil)
        cols.map { |c|
          cell = cell_for ? cell_for.call(c, values) : values[c.key].to_s
          cell = Ansi.truncate(cell, c.width, from: c.truncate_from) if Ansi.visible_length(cell) > c.width
          pad(cell, c.width, c.align)
        }.join(" " * @gap)
      end

      def used_width(cols)
        cols.sum(&:width) + (@gap * [cols.length - 1, 0].max)
      end

      private

      def drop_until_fits(cols, available_width)
        cols = cols.dup
        while used_width(cols) > available_width && cols.any? { |c| c.priority > 2 }
          victim = cols.select { |c| c.priority > 2 }.max_by(&:priority)
          cols.delete(victim)
        end
        cols
      end

      # Weighted columns (free-text fields like TITLE/DIRECTORY) get first
      # claim on any surplus — they're what a wider terminal is actually
      # "for". Weight-0 capped columns (PID, COST, CPU%...) only mop up
      # whatever's left after that: they have small, tight max deltas by
      # design, so they rarely go hungry even growing last. Growing them
      # FIRST instead (tried, and wrong) let a handful of small columns
      # eat all the surplus before TITLE ever got a look at it.
      def distribute_surplus(cols, available_width)
        surplus = available_width - used_width(cols)
        return cols if surplus <= 0

        grow_weighted_columns(cols, surplus)
        grow_fixed_columns(cols, available_width - used_width(cols))
        remaining = available_width - used_width(cols)
        grow_widest_column(cols, remaining) if remaining.positive?
        cols
      end

      # Weight-0 (fixed-intent) columns grow to their max, most essential
      # (lowest priority number) first — whatever surplus is left after
      # weighted columns have taken their share.
      def grow_fixed_columns(cols, surplus)
        cols.sort_by(&:priority).each do |c|
          break if surplus <= 0
          next if c.weight.positive? || c.max.nil?

          grow = [c.max - c.width, surplus].min
          next unless grow.positive?

          c.width += grow
          surplus -= grow
        end
      end

      # Remaining surplus is shared across weighted columns proportionally
      # to their weight, each capped at its own max.
      def grow_weighted_columns(cols, surplus)
        weighted = cols.select { |c| c.weight.positive? }
        return if surplus <= 0 || weighted.empty?

        total_weight = weighted.sum(&:weight)
        weighted.each do |c|
          share = (surplus * (c.weight.to_f / total_weight)).floor
          grow = c.max ? [c.max - c.width, share].min : share
          c.width += [grow, 0].max
        end
      end

      # Only a genuinely uncapped column can absorb unbounded leftover
      # surplus — a weighted or fixed column with a `max` must never grow
      # past it just because it happens to be the widest.
      def grow_widest_column(cols, surplus)
        target = cols.select { |c| c.max.nil? }.max_by(&:width)
        target.width += surplus if target
      end

      def pad(text, width, align)
        vlen = Ansi.visible_length(text)
        pad_n = [width - vlen, 0].max
        (align == :right) ? (" " * pad_n) + text : text + (" " * pad_n)
      end
    end
  end
end
