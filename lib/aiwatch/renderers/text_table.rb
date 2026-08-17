# frozen_string_literal: true

require_relative "../tui/ansi"

module Aiwatch
  module Renderers
    # Plain-text aligned grid: the alignment engine shared by Table (for
    # list/daily/show) and Live (for its own custom columns). Numeric-ish
    # columns can right-align; ANSI color codes are stripped when measuring
    # column widths so coloring text doesn't break alignment. ANSI handling
    # itself lives in Tui::Ansi — this module just calls through to it.
    #
    # Deliberately does NOT attempt to detect double-width Unicode glyphs —
    # see docs/decisions.md for why: some glyphs (e.g. U+25CF BLACK CIRCLE)
    # render wider than their character count in some terminals, which will
    # misalign a column that contains one. Only single-column-safe glyphs
    # (plain ASCII, Braille) should go in a column measured by this class.
    module TextTable
      module_function

      # max_widths: optional per-column cap (nil entries are uncapped). A
      # cell over its column's cap is truncated with a trailing "…" — for
      # unbounded fields like a project path or a model list, which
      # otherwise make the whole row wider than a normal terminal and wrap,
      # which looks exactly like broken column alignment (see
      # docs/decisions.md). Never applied to a column that may carry ANSI
      # color codes: truncation is byte/char-position based and would cut
      # mid-escape-sequence.
      def render(headers, rows, aligns = nil, max_widths: nil)
        aligns ||= Array.new(headers.length, :left)
        rows = rows.map { |row| cap_row(row, max_widths) }
        widths = headers.each_index.map do |i|
          ([visible_length(headers[i])] + rows.map { |r| visible_length(r[i]) }).max
        end

        lines = [headers.each_with_index.map { |h, i| justify(h, widths[i], :left) }.join("  ").rstrip]
        rows.each do |row|
          lines << row.each_with_index.map { |cell, i| justify(cell, widths[i], aligns[i]) }.join("  ").rstrip
        end
        lines.join("\n")
      end

      def justify(cell, width, align)
        pad = width - visible_length(cell)
        pad = 0 if pad.negative?
        (align == :right) ? (" " * pad) + cell.to_s : cell.to_s + (" " * pad)
      end

      def visible_length(cell)
        Tui::Ansi.visible_length(cell)
      end

      def truncate(cell, max)
        Tui::Ansi.truncate(cell, max)
      end

      def cap_row(row, max_widths)
        return row unless max_widths

        row.each_with_index.map { |cell, i| max_widths[i] ? truncate(cell, max_widths[i]) : cell }
      end
    end
  end
end
