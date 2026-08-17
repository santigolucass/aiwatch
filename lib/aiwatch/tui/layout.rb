# frozen_string_literal: true

require_relative "rect"

module Aiwatch
  module Tui
    # Computes the dashboard's screen regions from a terminal size. Pure
    # math, no drawing — Rects handed back here are what views draw into.
    #
    # Below MIN_WIDTH x MIN_HEIGHT there is no usable layout at all
    # (too_small: true, and the caller draws a single centered message
    # instead of a broken frame). Above that, the sidebar clamps to a
    # width range, drops out entirely below TABLE_MIN room for the table,
    # and the log panel drops out below room for a minimum-height body.
    module Layout
      MIN_WIDTH = 60
      MIN_HEIGHT = 20
      TABLE_MIN = 70
      SIDEBAR_MIN = 32
      SIDEBAR_MAX = 44
      BODY_MIN = 4
      TITLE_HEIGHT = 3
      STATS_HEIGHT = 3
      FOOTER_HEIGHT = 1

      Regions = Struct.new(:title, :stats, :table, :sidebar, :log, :footer, :too_small)

      module_function

      def compute(width, height)
        return Regions.new(too_small: true) if width < MIN_WIDTH || height < MIN_HEIGHT

        log_h = log_height(height)
        body_h = [height - TITLE_HEIGHT - STATS_HEIGHT - log_h - FOOTER_HEIGHT, BODY_MIN].max
        sidebar_w = sidebar_width(width)
        table_w = width - sidebar_w

        row = 0
        title = Rect.new(row, 0, width, TITLE_HEIGHT)
        row += TITLE_HEIGHT
        stats = Rect.new(row, 0, width, STATS_HEIGHT)
        row += STATS_HEIGHT
        table = Rect.new(row, 0, table_w, body_h)
        sidebar = sidebar_w.positive? ? Rect.new(row, table_w, sidebar_w, body_h) : nil
        row += body_h
        log = log_h.positive? ? Rect.new(row, 0, width, log_h) : nil
        row += log_h
        footer = Rect.new(row, 0, width, FOOTER_HEIGHT)

        Regions.new(title: title, stats: stats, table: table, sidebar: sidebar, log: log, footer: footer, too_small: false)
      end

      def log_height(height)
        fixed = TITLE_HEIGHT + STATS_HEIGHT + FOOTER_HEIGHT + BODY_MIN
        return 0 if height - fixed < 6

        (height * 0.28).round.clamp(6, 14).clamp(0, height - fixed)
      end

      def sidebar_width(width)
        candidate = (width * 0.25).round.clamp(SIDEBAR_MIN, SIDEBAR_MAX)
        (width - candidate < TABLE_MIN) ? 0 : candidate
      end
    end
  end
end
