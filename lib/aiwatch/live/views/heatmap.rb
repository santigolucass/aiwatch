# frozen_string_literal: true

module Aiwatch
  module Live
    module Views
      # Cost per local calendar day across every discovered session,
      # reusing DailyAggregator (the same rollup `aiwatch daily` uses) —
      # rendered as a bar per day rather than an hour x day grid, since
      # Session only retains (date, model) granularity, not hourly.
      module Heatmap
        module_function

        def draw(canvas, regions, theme:, sessions:, cost_calculator:, now:)
          rect = Tui::Rect.new(0, 0, canvas.width, canvas.height - 1)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Heatmap — cost per day")
          return if inner.empty?

          days = DailyAggregator.new(cost_calculator).aggregate(sessions.map(&:session)).first(inner.height)
          if days.empty?
            canvas.write(inner.row, inner.col, "(no usage recorded yet)", max: inner.width)
            return
          end

          max_cost = days.map { |d| d[:cost] }.max
          max_cost = 1.0 if max_cost.nil? || max_cost <= 0
          label_width = 12
          bar_width = [inner.width - label_width - 12, 4].max

          days.each_with_index do |day, i|
            draw_row(canvas, inner, i, theme, day, max_cost, bar_width, label_width)
          end
        end

        def draw_row(canvas, inner, row_offset, theme, day, max_cost, bar_width, label_width)
          filled = (bar_width * (day[:cost] / max_cost)).round.clamp(0, bar_width)
          bar = (theme.glyph(:bar_full) * filled) + (theme.glyph(:bar_empty) * (bar_width - filled))
          date_label = day[:date].to_s.ljust(label_width)
          line = "#{date_label}#{theme.paint(bar, :accent)}  #{Format.cost(day[:cost])}"
          canvas.write(inner.row + row_offset, inner.col, line, max: inner.width)
        end
      end
    end
  end
end
