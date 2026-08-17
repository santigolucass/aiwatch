# frozen_string_literal: true

module Aiwatch
  module Live
    module Widgets
      module SessionTable
        COLUMNS = [
          {key: :cursor, width: 1, priority: 0},
          {key: :pid, header: "PID", min: 5, max: 7, align: :right, priority: 1},
          {key: :status, header: "STATUS", min: 6, max: 8, priority: 1},
          {key: :ctx, header: "CTX", min: 5, max: 6, align: :right, priority: 1},
          {key: :title, header: "TITLE", min: 10, max: 60, weight: 3, priority: 2},
          {key: :cost, header: "COST", min: 6, max: 9, align: :right, priority: 3},
          {key: :cpu, header: "CPU%", min: 5, max: 6, align: :right, priority: 4},
          {key: :mem, header: "MEM%", min: 5, max: 6, align: :right, priority: 4},
          {key: :started, header: "STARTED", min: 5, max: 8, priority: 5},
          {key: :branch, header: "BRANCH", min: 6, max: 20, weight: 1, priority: 6},
          {key: :model, header: "MODEL", min: 6, max: 16, weight: 1, priority: 7},
          {key: :dir, header: "DIRECTORY", min: 10, max: 40, weight: 2, priority: 8, truncate_from: :left},
          {key: :cpuhist, header: "CPU-HIST", width: 12, priority: 9}
        ].freeze

        SPARKLINE_WIDTH = 6 # Braille chars, 2 samples each -> 12 columns

        module_function

        def draw(canvas, rect, theme:, sessions:, selected_id:, cost_calculator:, context_limit_for:, now:)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Claude Code (#{sessions.length})")
          return if inner.empty?

          grid = Tui::Grid.new(COLUMNS)
          cols = grid.layout(inner.width)
          canvas.write(inner.row, inner.col, grid.render_header(cols, theme: theme), max: inner.width)

          visible_rows = [inner.height - 1, 0].max
          sessions.first(visible_rows).each_with_index do |session, i|
            selected = session.id == selected_id
            row = grid.render_row(cols, row_values(session, cost_calculator, context_limit_for, now, selected))
            row = theme.paint(row, :accent, bold: true) if selected
            canvas.write(inner.row + 1 + i, inner.col, row, max: inner.width)
          end
        end

        def row_values(session, cost_calculator, context_limit_for, now, selected)
          total = cost_calculator.total_for(session.session)
          limit = context_limit_for.call(session.ctx_model)
          {
            cursor: selected ? ">" : " ",
            pid: session.pid || "-",
            status: session.dead? ? "DEAD" : "ACTIVE",
            ctx: ctx_cell(session, limit),
            title: session.title || "?",
            cost: "#{"~" if session.totals_partial?}#{Format.cost(total.amount, unknown: !total.fully_known?)}",
            cpu: session.cpu_percent ? session.cpu_percent.round.to_s : "-",
            mem: session.mem_percent ? session.mem_percent.round.to_s : "-",
            started: Format.uptime(session.first_seen_at, now: now),
            branch: session.branch || "-",
            model: session.ctx_model || session.models.first || "?",
            dir: session.project || "?",
            cpuhist: Renderers::BrailleSparkline.render(session.cpu_history.to_a, width: SPARKLINE_WIDTH)
          }
        end

        def ctx_cell(session, limit)
          return "?" unless limit && session.ctx_tokens

          Format.percent(session.ctx_tokens.to_f / limit)
        end
      end
    end
  end
end
