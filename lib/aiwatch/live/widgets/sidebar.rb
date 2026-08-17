# frozen_string_literal: true

module Aiwatch
  module Live
    module Widgets
      module Sidebar
        DETAIL_HEIGHT = 13
        TOKENS_HEIGHT = 8
        MIN_CONTEXT_HEIGHT = 8

        module_function

        def draw(canvas, rect, theme:, session:, cost_calculator:, context_limit_for:, now:)
          return if rect.nil? || rect.empty?

          if rect.height < DETAIL_HEIGHT + TOKENS_HEIGHT + MIN_CONTEXT_HEIGHT
            draw_detail(canvas, rect, theme: theme, session: session, now: now)
            return
          end

          context_h = rect.height - DETAIL_HEIGHT - TOKENS_HEIGHT
          detail_rect, tokens_rect, context_rect = rect.split_v(DETAIL_HEIGHT, TOKENS_HEIGHT, context_h)

          draw_detail(canvas, detail_rect, theme: theme, session: session, now: now)
          draw_tokens(canvas, tokens_rect, theme: theme, session: session, cost_calculator: cost_calculator)
          draw_context(canvas, context_rect, theme: theme, session: session, context_limit_for: context_limit_for)
        end

        def draw_detail(canvas, rect, theme:, session:, now:)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Session Detail")
          return unless session

          lines = [
            "PID:        #{session.pid || "-"}",
            "Status:     #{session.dead? ? "DEAD" : "ACTIVE"}",
            "Model:      #{session.ctx_model || session.models.first || "?"}",
            "Branch:     #{session.branch || "-"}",
            "Started:    #{Format.relative_time(session.first_seen_at, now: now)}",
            "CPU:        #{pct(session.cpu_percent)}",
            "MEM:        #{pct(session.mem_percent)}",
            "Stop:       #{session.stop_reason || "-"}",
            "Permission: #{session.permission_mode || "-"}",
            "Version:    #{session.cli_version || "-"}"
          ]
          write_lines(canvas, inner, lines)
        end

        def draw_tokens(canvas, rect, theme:, session:, cost_calculator:)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Tokens")
          return unless session

          total = cost_calculator.total_for(session.session)
          lines = [
            "In:  #{Format.tokens(session.total_input_tokens)}    Out: #{Format.tokens(session.total_output_tokens)}",
            "Cache R: #{Format.tokens(session.total_cache_read_tokens)}  W: #{Format.tokens(session.total_cache_creation_tokens)}",
            "Turn:  #{Format.duration_ms(session.turn_ms)}",
            "Compactions: #{session.compactions}",
            "Cost:  #{"~" if session.totals_partial?}#{Format.cost(total.amount, unknown: !total.fully_known?)}"
          ]
          write_lines(canvas, inner, lines)
        end

        def draw_context(canvas, rect, theme:, session:, context_limit_for:)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Context Window")
          return unless session

          limit = context_limit_for.call(session.ctx_model)
          breakdown = ContextWindow.breakdown(
            input: session.ctx_input_tokens, cache_write: session.ctx_cache_creation_tokens,
            cache_read: session.ctx_cache_read_tokens, output: session.ctx_output_tokens, limit: limit
          )
          return write_lines(canvas, inner, ["Context window: unknown model"]) unless breakdown

          draw_bar(canvas, inner, theme, breakdown)
          legend = [
            "Input #{pct(breakdown.input_pct)}   Cache W #{pct(breakdown.cache_write_pct)}",
            "Cache R #{pct(breakdown.cache_read_pct)}   Output #{pct(breakdown.output_pct)}",
            "Free #{pct(breakdown.free_pct)}"
          ]
          write_lines(canvas, inner, legend, offset: 2)
        end

        def draw_bar(canvas, inner, theme, breakdown)
          return if inner.width < 1

          filled = (inner.width * [breakdown.occupied.to_f / breakdown.limit, 1.0].min).round
          bar = (theme.glyph(:bar_full) * filled) + (theme.glyph(:bar_empty) * (inner.width - filled))
          canvas.write(inner.row, inner.col, theme.paint(bar, :accent), max: inner.width)
        end

        def write_lines(canvas, inner, lines, offset: 0)
          lines.first([inner.height - offset, 0].max).each_with_index do |line, i|
            canvas.write(inner.row + offset + i, inner.col, line, max: inner.width)
          end
        end

        def pct(value)
          value ? "#{value.round}%" : "-"
        end
      end
    end
  end
end
