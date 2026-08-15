# frozen_string_literal: true

module Aiwatch
  module Renderers
    # Table output for list/daily/show, built on TextTable's alignment
    # engine. Active sessions are shown by coloring the SESSION id itself
    # (bold green) rather than a separate marker glyph — an earlier version
    # used a leading "●" column, which misaligned in terminals that render
    # that glyph as double-width (see docs/decisions.md).
    class Table
      LIST_HEADERS = ["SESSION", "PROJECT", "MODEL(S)", "INPUT", "OUTPUT", "CACHE R/W", "COST (USD)", "LAST ACTIVITY"].freeze
      LIST_ALIGN = [:left, :left, :left, :right, :right, :right, :right, :left].freeze

      DAILY_HEADERS = ["DATE", "SESSIONS", "INPUT", "OUTPUT", "CACHE R/W", "COST (USD)"].freeze
      DAILY_ALIGN = [:left, :right, :right, :right, :right, :right].freeze

      def initialize(cost_calculator)
        @cost_calculator = cost_calculator
      end

      def render_list(sessions, now: Time.now, color: false, active_threshold_minutes: 5)
        rows = sessions.map { |s| list_row(s, now, color, active_threshold_minutes) }
        TextTable.render(LIST_HEADERS, rows, LIST_ALIGN)
      end

      def render_daily(daily_rows)
        TextTable.render(DAILY_HEADERS, daily_rows.map { |d| daily_row(d) }, DAILY_ALIGN)
      end

      def render_show(session, now: Time.now)
        total = @cost_calculator.total_for(session)
        lines = []
        lines << "Session:  #{session.id}"
        lines << "Project:  #{session.project || "?"}"
        lines << "Activity: #{Format.relative_time(session.first_seen_at, now: now)} -> #{Format.relative_time(session.last_seen_at, now: now)}"
        lines << "Cost:     #{Format.cost(total.amount, unknown: !total.fully_known?)}"
        lines << ""
        headers = ["MODEL", "INPUT", "OUTPUT", "CACHE READ", "CACHE CREATE", "COST (USD)"]
        rows = session.model_usages.values.map do |usage|
          model_cost = @cost_calculator.cost_for(usage)
          [
            usage.model,
            Format.tokens(usage.input_tokens),
            Format.tokens(usage.output_tokens),
            Format.tokens(usage.cache_read_tokens),
            Format.tokens(usage.cache_creation_tokens),
            Format.cost(model_cost, unknown: model_cost.nil?)
          ]
        end
        lines << TextTable.render(headers, rows, [:left, :right, :right, :right, :right, :right])
        unless total.fully_known?
          lines << ""
          lines << "Warning: no pricing data for: #{total.unknown_models.join(", ")}"
        end
        lines.join("\n")
      end

      private

      def list_row(session, now, color, active_threshold_minutes)
        total = @cost_calculator.total_for(session)
        active = session.active?(now: now, threshold_minutes: active_threshold_minutes)
        [
          session_id_cell(session, active, color),
          session.project || "?",
          session.models.join(","),
          Format.tokens(session.total_input_tokens),
          Format.tokens(session.total_output_tokens),
          "#{Format.tokens(session.total_cache_read_tokens)}/#{Format.tokens(session.total_cache_creation_tokens)}",
          Format.cost(total.amount, unknown: !total.fully_known?),
          Format.relative_time(session.last_seen_at, now: now)
        ]
      end

      def session_id_cell(session, active, color)
        return session.short_id unless active && color

        "\e[1;32m#{session.short_id}\e[0m"
      end

      def daily_row(day)
        [
          day[:date].to_s,
          day[:session_count].to_s,
          Format.tokens(day[:input_tokens]),
          Format.tokens(day[:output_tokens]),
          "#{Format.tokens(day[:cache_read_tokens])}/#{Format.tokens(day[:cache_creation_tokens])}",
          Format.cost(day[:cost], unknown: !day[:fully_known])
        ]
      end
    end
  end
end
