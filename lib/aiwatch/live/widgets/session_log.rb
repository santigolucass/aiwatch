# frozen_string_literal: true

module Aiwatch
  module Live
    module Widgets
      module SessionLog
        BULLET_ROLES = {
          assistant: :active, tool: :accent, user: :header, result: :muted,
          system: :muted, compact: :warning, pr: :cost
        }.freeze

        module_function

        def draw(canvas, rect, theme:, session:)
          title = session ? "Session Log: #{session.project || session.short_id}" : "Session Log"
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: title)
          return if inner.empty? || session.nil?

          events = session.feed.to_a.last(inner.height)
          events.each_with_index do |event, i|
            canvas.write(inner.row + i, inner.col, format_event(theme, event), max: inner.width)
          end
        end

        def format_event(theme, event)
          time = event.at ? Format.clock(event.at) : "--:--:--"
          bullet = theme.paint(theme.glyph(:active_dot), BULLET_ROLES.fetch(event.kind, :muted))
          "#{time} #{bullet} #{event.kind.to_s.upcase.ljust(9)} #{event.text}"
        end
      end
    end
  end
end
