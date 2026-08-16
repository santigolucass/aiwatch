# frozen_string_literal: true

require "io/console"

module Aiwatch
  module Renderers
    # Auto-refreshing view of currently-active sessions, with a per-session
    # colored Braille sparkline of its recent token throughput (tokens/tick,
    # floored at 0) — each session keeps the same color for the life of the
    # run, assigned in first-seen order from a small fixed palette.
    #
    # Puts the terminal into raw mode so a bare 'q' (or Ctrl-C, sent as byte
    # 0x03 in raw mode) quits instantly without waiting for Enter, and
    # always restores the terminal on the way out — including on an
    # unhandled exception.
    class Live
      REFRESH_SECONDS = 2
      SPARKLINE_WIDTH = 20 # Braille characters; each holds 2 samples
      PALETTE = [32, 36, 33, 35, 34, 31].freeze # green, cyan, yellow, magenta, blue, red

      def initialize(adapter:, cost_calculator:, out: $stdout, in_stream: $stdin,
        active_threshold_minutes: 5, refresh_seconds: REFRESH_SECONDS, sparkline_width: SPARKLINE_WIDTH,
        clock: -> { Time.now }, quit_requested: nil)
        @adapter = adapter
        @cost_calculator = cost_calculator
        @out = out
        @in = in_stream
        @active_threshold_minutes = active_threshold_minutes
        @refresh_seconds = refresh_seconds
        @sparkline_width = sparkline_width
        @clock = clock
        @quit_requested = quit_requested || method(:terminal_quit_requested)

        @history = Hash.new { |h, k| h[k] = [] }
        @previous_totals = {}
        @session_colors = {}
      end

      def run
        setup_terminal
        loop do
          render_once
          break if @quit_requested.call(@refresh_seconds)
        end
      ensure
        restore_terminal
      end

      private

      def render_once
        now = @clock.call
        sessions = active_sessions(now)
        record_tick(sessions)

        @out.print "\e[H\e[2J"
        @out.puts "aiwatch live — #{now.strftime("%H:%M:%S")} — #{sessions.length} active session(s) — press q to quit"
        @out.puts
        @out.puts sessions.empty? ? "(no active sessions)" : session_table(sessions, now)
        @out.flush if @out.respond_to?(:flush)
      end

      def active_sessions(now)
        sessions = @adapter.discover_sessions.select do |s|
          s.active?(now: now, threshold_minutes: @active_threshold_minutes)
        end
        sessions.sort_by { |s| s.last_seen_at || Time.at(0) }.reverse
      end

      # Records this tick's token delta per session (floored at 0, in case
      # of a transient under-read from a concurrently-written log file) and
      # assigns first-seen sessions a stable color.
      def record_tick(sessions)
        sessions.each do |session|
          total = session.total_input_tokens + session.total_output_tokens
          previous = @previous_totals[session.id]
          delta = previous.nil? ? 0 : [total - previous, 0].max
          @previous_totals[session.id] = total

          history = @history[session.id]
          history << delta
          history.shift while history.length > @sparkline_width * 2

          @session_colors[session.id] ||= PALETTE[@session_colors.size % PALETTE.length]
        end
      end

      # PROJECT and MODEL(S) are capped the same way as in Table — see
      # docs/decisions.md.
      COLUMN_MAX_WIDTHS = [nil, 28, 24, nil, nil, nil].freeze

      def session_table(sessions, now)
        color = @out.respond_to?(:tty?) && @out.tty?
        headers = ["SESSION", "PROJECT", "MODEL(S)", "COST (USD)", "TOKENS/s (#{window_label})", "LAST ACTIVITY"]
        rows = sessions.map { |s| session_row(s, now, color) }
        TextTable.render(headers, rows, [:left, :left, :left, :right, :left, :left], max_widths: COLUMN_MAX_WIDTHS)
      end

      def session_row(session, now, color)
        total = @cost_calculator.total_for(session)
        ansi = @session_colors[session.id]
        sparkline = BrailleSparkline.render(@history[session.id], width: @sparkline_width)
        [
          colorize(session.short_id, ansi, color, bold: true),
          session.project || "?",
          session.models.join(","),
          Format.cost(total.amount, unknown: !total.fully_known?),
          colorize(sparkline, ansi, color),
          Format.relative_time(session.last_seen_at, now: now)
        ]
      end

      def colorize(text, ansi_color, enabled, bold: false)
        return text unless enabled

        "\e[#{"1;" if bold}#{ansi_color}m#{text}\e[0m"
      end

      def window_label
        "#{(@sparkline_width * 2 * @refresh_seconds).round}s"
      end

      def terminal_quit_requested(timeout)
        ready = IO.select([@in], nil, nil, timeout)
        return false unless ready

        char = @in.getc
        char == "q" || char == ""
      rescue IOError, Errno::EBADF, Errno::ENOTTY
        false
      end

      def setup_terminal
        @in.raw! if @in.respond_to?(:raw!)
      rescue IOError, Errno::ENOTTY
        nil
      end

      def restore_terminal
        @in.cooked! if @in.respond_to?(:cooked!)
        @out.print "\e[?25h" if @out.respond_to?(:print)
      rescue IOError, Errno::ENOTTY
        nil
      end
    end
  end
end
