# frozen_string_literal: true

module Aiwatch
  module Live
    module Widgets
      # Three plain text rows (no box) summarizing everything the table
      # below shows in detail: counts, totals, and the clock.
      module StatsBar
        module_function

        # "Sessions" (active/dead/total) counts top-level sessions only —
        # a subagent isn't a session in that sense, it's detail under
        # one. Token/cost totals sum across everything in `sessions`
        # (including subagents), since that's real spend regardless of
        # which row it's attributed to.
        def draw(canvas, rect, theme:, sessions:, now:, total_cost:)
          top_level = sessions.reject(&:subagent?)
          active = top_level.count { |s| !s.dead? }
          dead = top_level.count(&:dead?)
          total_in = sessions.sum { |s| s.total_input_tokens || 0 }
          total_out = sessions.sum { |s| s.total_output_tokens || 0 }
          total_cache = sessions.sum { |s| (s.total_cache_read_tokens || 0) + (s.total_cache_creation_tokens || 0) }

          line1 = "#{theme.paint(theme.glyph(:active_dot), :active)} #{active} active   " \
            "#{theme.paint(theme.glyph(:dead_dot), :dead)} #{dead} dead   |   " \
            "Cost: #{Format.cost(total_cost)}   |   #{Format.clock(now)}"
          line2 = "Tokens  In: #{Format.count(total_in)}   Out: #{Format.count(total_out)}   Cache: #{Format.count(total_cache)}"
          line3 = "Sessions: #{active} active  #{dead} dead  #{top_level.length} total#{avg_ctx_suffix(sessions)}"

          canvas.write(rect.row, rect.col, line1, max: rect.width)
          canvas.write(rect.row + 1, rect.col, line2, max: rect.width)
          canvas.write(rect.row + 2, rect.col, theme.paint(line3, :muted), max: rect.width)
        end

        def avg_ctx_suffix(sessions)
          known = sessions.filter_map(&:ctx_tokens)
          return "" if known.empty?

          "   |   Avg tokens/turn: #{Format.count((known.sum / known.length.to_f).round)}"
        end
      end
    end
  end
end
