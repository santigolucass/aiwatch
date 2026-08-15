# frozen_string_literal: true

module Aiwatch
  module Renderers
    # Plain-text aligned grid: the alignment engine shared by Table (for
    # list/daily/show) and Live (for its own custom columns). Numeric-ish
    # columns can right-align; ANSI color codes are stripped when measuring
    # column widths so coloring text doesn't break alignment.
    #
    # Deliberately does NOT attempt to detect double-width Unicode glyphs —
    # see docs/decisions.md for why: some glyphs (e.g. U+25CF BLACK CIRCLE)
    # render wider than their character count in some terminals, which will
    # misalign a column that contains one. Only single-column-safe glyphs
    # (plain ASCII, Braille) should go in a column measured by this class.
    module TextTable
      ANSI = /\e\[[0-9;]*m/

      module_function

      def render(headers, rows, aligns = nil)
        aligns ||= Array.new(headers.length, :left)
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
        cell.to_s.gsub(ANSI, "").length
      end
    end
  end
end
