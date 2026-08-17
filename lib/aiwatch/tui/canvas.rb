# frozen_string_literal: true

require_relative "ansi"

module Aiwatch
  module Tui
    # A width x height grid that every widget draws into. Writes clip at
    # the canvas edge (and at an optional per-write `max`), which is what
    # makes "this line is too wide" structurally impossible instead of
    # merely tested for — every rendering bug logged in docs/decisions.md
    # (the "●" marker, the column caps, the "\r\n" cascade) came from
    # building frames by concatenating strings and hoping they fit.
    #
    # Backed by a per-cell grid, not a list of row spans: a write fully
    # overwrites whichever individual columns it touches and leaves every
    # other column on that row untouched, so a later write (e.g. a box's
    # title label) correctly paints over part of an earlier one (e.g. the
    # box's top border) instead of being dropped as "overlapping".
    class Canvas
      Cell = Struct.new(:ch, :pre, :post)

      attr_reader :width, :height

      def initialize(width:, height:)
        @width = width
        @height = height
        @cells = Array.new(height) { Array.new(width) { Cell.new(" ", "", "") } }
      end

      # Writes `text` at (row, col). Clips to whatever's smaller of the
      # canvas edge and `max`. Text carrying ANSI color codes is clipped
      # color-aware (see Tui::Ansi) so a truncated colored cell can't
      # bleed color into what follows; text carrying raw control bytes
      # (a literal newline embedded in real conversation content shown
      # by the session log, say) is sanitized first, so it can't move
      # the real cursor and corrupt whatever the next row's write lands
      # on. Silently no-ops outside the canvas — a widget computing a
      # bad coordinate should not crash the frame.
      def write(row, col, text, max: nil)
        return if row.negative? || row >= height || col.negative? || col >= width

        avail = width - col
        avail = [avail, max].min if max
        return if avail <= 0

        place(row, col, clip_to_fit(Ansi.sanitize(text), avail))
      end

      # Fills a rect with a repeated single (possibly colored) cell —
      # typically a themed background color painted over a space.
      def fill(rect, cell_text)
        return if rect.empty?

        row_start = [rect.row, 0].max
        row_end = [rect.row + rect.height, height].min
        col_start = [rect.col, 0].max
        col_end = [rect.col + rect.width, width].min
        return if row_end <= row_start || col_end <= col_start

        span = cell_text * (col_end - col_start)
        (row_start...row_end).each { |r| write(r, col_start, span) }
      end

      # Array<String>, exactly `height` long, each exactly `width` visible
      # columns (every cell is always exactly one visible character).
      def to_lines
        @cells.map { |row| row.map { |c| "#{c.pre}#{c.ch}#{c.post}" }.join }
      end

      private

      # Trailing codes with no following character in this write (e.g. a
      # closing reset after the last visible char) attach to that last
      # character's own `post`, not to whatever cell happens to come
      # next — a later, unrelated write landing on that neighboring cell
      # must not silently swallow this write's own closing reset.
      def place(row, col, text)
        pending = +""
        c = col
        last_cell = nil
        Ansi.scan(text) do |code, char|
          if code
            pending << code
          else
            cell = @cells[row][c]
            cell.pre = pending
            cell.ch = char
            cell.post = ""
            pending = +""
            last_cell = cell
            c += 1
          end
        end
        last_cell.post = pending if last_cell && !pending.empty?
      end

      def clip_to_fit(text, avail)
        return "" if avail <= 0

        vlen = Ansi.visible_length(text)
        return text if vlen <= avail

        clipped = Ansi.truncate(text, avail)
        (Ansi.visible_length(clipped) <= avail) ? clipped : Ansi.hard_truncate(text, avail)
      end
    end
  end
end
