# frozen_string_literal: true

# Parses the raw escape-sequence output Screen#flush writes (absolute
# per-row positioning, no bare newlines) back into a row-indexed grid,
# so tests can assert structurally ("row 9 contains...", "no row exceeds
# the terminal width") instead of matching brittle substrings across an
# unbroken byte stream.
class Frame
  Row = Struct.new(:number, :raw, :plain) do
    def include?(text)
      plain.include?(text)
    end
  end

  attr_reader :rows

  # Screen writes are never followed by anything else mid-row except the
  # next row's own "\e[<n>;1H" positioning escape — except the very last
  # row of a frame, which can be immediately followed by Screen-level
  # bookkeeping (cursor show/hide, alt-screen toggle) that isn't part of
  # that row's actual content and must not be counted as if it were.
  TRAILING_SCREEN_ESCAPES = /(\e\[\?25[hl]|\e\[\?1049[hl])+\z/

  def initialize(raw_output)
    @rows = {}
    parts = raw_output.split(/\e\[(\d+);1H/)
    parts.shift
    parts.each_slice(2) do |row_number, rest|
      content = rest.sub(/\A\e\[K/, "").sub(TRAILING_SCREEN_ESCAPES, "")
      n = row_number.to_i
      @rows[n] = Row.new(n, content, Aiwatch::Tui::Ansi.strip(content))
    end
  end

  # Splits raw Screen output into one Frame per repaint. The very first
  # chunk is whatever Screen#enter wrote before any row content (cursor
  # hide, alt-screen switch) and never contains a row itself, so it's
  # dropped rather than yielded as a bogus empty leading frame.
  def self.frames(raw_output)
    raw_output.split(/(?=\e\[1;1H)/).reject(&:empty?).map { |chunk| new(chunk) }.reject { |f| f.rows.empty? }
  end

  def [](row_number)
    @rows[row_number]
  end

  def row_containing(text)
    @rows.values.find { |r| r.include?(text) }
  end

  def each_row(&block)
    @rows.values.sort_by(&:number).each(&block)
  end

  def max_width
    @rows.values.map { |r| r.plain.length }.max || 0
  end
end
