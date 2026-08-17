# frozen_string_literal: true

module Aiwatch
  module Live
    module Views
      # Sessions that exist on disk but fell outside the active window —
      # everything the dashboard's live table doesn't show. Renders fine
      # on a session whose totals are still backfilling; it just fills in
      # as SessionStore catches up, same as the live table does.
      module History
        COLUMNS = [
          {key: :title, header: "TITLE", min: 15, max: 60, weight: 2, priority: 1},
          {key: :project, header: "PROJECT", min: 10, max: 40, weight: 1, priority: 2, truncate_from: :left},
          {key: :last, header: "LAST ACTIVITY", min: 10, max: 14, priority: 1},
          {key: :cost, header: "COST", min: 6, max: 10, align: :right, priority: 1}
        ].freeze

        module_function

        def draw(canvas, regions, theme:, all_sessions:, active_sessions:, cost_calculator:, now:)
          rect = Tui::Rect.new(0, 0, canvas.width, canvas.height - 1)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "History — inactive sessions")
          return if inner.empty?

          active_ids = active_sessions.map(&:id).to_h { |id| [id, true] }
          history = all_sessions.reject { |s| active_ids[s.id] }.sort_by { |s| s.last_seen_at || Time.at(0) }.reverse

          if history.empty?
            canvas.write(inner.row, inner.col, "(no inactive sessions found)", max: inner.width)
            return
          end

          grid = Tui::Grid.new(COLUMNS)
          cols = grid.layout(inner.width)
          canvas.write(inner.row, inner.col, grid.render_header(cols, theme: theme), max: inner.width)

          history.first([inner.height - 1, 0].max).each_with_index do |session, i|
            total = cost_calculator.total_for(session.session)
            row = grid.render_row(cols, {
              title: session.title || "?",
              project: session.project || "?",
              last: Format.relative_time(session.last_seen_at, now: now),
              cost: Format.cost(total.amount, unknown: !total.fully_known?)
            })
            canvas.write(inner.row + 1 + i, inner.col, row, max: inner.width)
          end
        end
      end
    end
  end
end
