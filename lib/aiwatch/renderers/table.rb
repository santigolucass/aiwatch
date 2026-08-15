# frozen_string_literal: true

module Aiwatch
  module Renderers
    # Plain-text aligned tables. Numeric-ish columns right-align; the rest
    # left-align. ANSI color codes (used only for the active marker) are
    # stripped when measuring column widths so alignment doesn't break.
    class Table
      LIST_HEADERS = ["", "SESSION", "PROJECT", "MODEL(S)", "INPUT", "OUTPUT", "CACHE R/W", "COST (USD)", "LAST ACTIVITY"].freeze
      LIST_ALIGN = [:left, :left, :left, :left, :right, :right, :right, :right, :left].freeze

      DAILY_HEADERS = ["DATE", "SESSIONS", "INPUT", "OUTPUT", "CACHE R/W", "COST (USD)"].freeze
      DAILY_ALIGN = [:left, :right, :right, :right, :right, :right].freeze

      ANSI = /\e\[[0-9;]*m/

      def initialize(cost_calculator)
        @cost_calculator = cost_calculator
      end

      def render_list(sessions, now: Time.now, color: false, active_threshold_minutes: 5)
        rows = sessions.map { |s| list_row(s, now, color, active_threshold_minutes) }
        render_table(LIST_HEADERS, rows, LIST_ALIGN)
      end

      def render_daily(daily_rows)
        render_table(DAILY_HEADERS, daily_rows.map { |d| daily_row(d) }, DAILY_ALIGN)
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
        lines << render_table(headers, rows, [:left, :right, :right, :right, :right, :right])
        unless total.fully_known?
          lines << ""
          lines << "Warning: no pricing data for: #{total.unknown_models.join(", ")}"
        end
        lines.join("\n")
      end

      private

      def list_row(session, now, color, active_threshold_minutes)
        total = @cost_calculator.total_for(session)
        [
          active_marker(session, now, color, active_threshold_minutes),
          session.short_id,
          session.project || "?",
          session.models.join(","),
          Format.tokens(session.total_input_tokens),
          Format.tokens(session.total_output_tokens),
          "#{Format.tokens(session.total_cache_read_tokens)}/#{Format.tokens(session.total_cache_creation_tokens)}",
          Format.cost(total.amount, unknown: !total.fully_known?),
          Format.relative_time(session.last_seen_at, now: now)
        ]
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

      def active_marker(session, now, color, threshold_minutes)
        return "" unless session.active?(now: now, threshold_minutes: threshold_minutes)

        color ? "\e[32m●\e[0m" : "●"
      end

      def render_table(headers, rows, aligns = nil)
        aligns ||= Array.new(headers.length, :left)
        widths = headers.each_index.map do |i|
          ([visible_length(headers[i])] + rows.map { |r| visible_length(r[i]) }).max
        end

        lines = [headers.each_with_index.map { |h, i| justify(h, widths[i], :left) }.join("  ").rstrip]
        rows.each do |row|
          lines << row.each_with_index.map { |cell, i| justify(cell, widths[i], aligns[i]) }.join("  ").rstrip
        end
        lines.join("\n")
      end

      def justify(cell, width, align)
        pad = width - visible_length(cell)
        pad = 0 if pad.negative?
        (align == :right) ? (" " * pad) + cell.to_s : cell.to_s + (" " * pad)
      end

      def visible_length(cell)
        cell.to_s.gsub(ANSI, "").length
      end
    end
  end
end
