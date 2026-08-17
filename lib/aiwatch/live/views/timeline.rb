# frozen_string_literal: true

module Aiwatch
  module Live
    module Views
      # Every visible session's recent token-throughput history as one
      # sparkline row — the same per-tick data the dashboard's table
      # would need a CPU-HIST-style column to show for tokens instead of
      # CPU, pulled out into its own full-width view since a session's
      # whole title fits next to it here.
      module Timeline
        SPARKLINE_WIDTH = 30

        module_function

        def draw(canvas, regions, theme:, sessions:, now:)
          rect = Tui::Rect.new(0, 0, canvas.width, canvas.height - 1)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Timeline — recent token throughput per session")
          return if inner.empty?

          if sessions.empty?
            canvas.write(inner.row, inner.col, "(no active sessions)", max: inner.width)
            return
          end

          sessions.first(inner.height).each_with_index do |session, i|
            draw_row(canvas, inner, i, theme, session, now)
          end
        end

        def draw_row(canvas, inner, row_offset, theme, session, now)
          sparkline = Renderers::BrailleSparkline.render(session.token_history.to_a, width: SPARKLINE_WIDTH)
          label_width = [inner.width - SPARKLINE_WIDTH - 3, 10].max
          label = Tui::Ansi.truncate("#{session.title || "?"} (#{Format.relative_time(session.last_seen_at, now: now)})", label_width)
          line = "#{sparkline}  #{label}"
          canvas.write(inner.row + row_offset, inner.col, line, max: inner.width)
        end
      end
    end
  end
end
