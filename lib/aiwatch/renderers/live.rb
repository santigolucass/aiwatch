# frozen_string_literal: true

require "io/console"

module Aiwatch
  module Renderers
    # Auto-refreshing view of currently-active sessions. Puts the terminal
    # into raw mode so a bare 'q' (or Ctrl-C, sent as byte 0x03 in raw mode)
    # quits instantly without waiting for Enter, and always restores the
    # terminal on the way out — including on an unhandled exception.
    class Live
      REFRESH_SECONDS = 2

      def initialize(adapter:, cost_calculator:, out: $stdout, in_stream: $stdin,
        active_threshold_minutes: 5, refresh_seconds: REFRESH_SECONDS,
        clock: -> { Time.now }, quit_requested: nil)
        @adapter = adapter
        @cost_calculator = cost_calculator
        @out = out
        @in = in_stream
        @active_threshold_minutes = active_threshold_minutes
        @refresh_seconds = refresh_seconds
        @clock = clock
        @quit_requested = quit_requested || method(:terminal_quit_requested)
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

        @out.print "\e[H\e[2J"
        @out.puts "aiwatch live — #{now.strftime("%H:%M:%S")} — #{sessions.length} active session(s) — press q to quit"
        @out.puts
        if sessions.empty?
          @out.puts "(no active sessions)"
        else
          table = Renderers::Table.new(@cost_calculator).render_list(
            sessions, now: now, color: @out.respond_to?(:tty?) && @out.tty?,
            active_threshold_minutes: @active_threshold_minutes
          )
          @out.puts table
        end
        @out.flush if @out.respond_to?(:flush)
      end

      def active_sessions(now)
        sessions = @adapter.discover_sessions.select do |s|
          s.active?(now: now, threshold_minutes: @active_threshold_minutes)
        end
        sessions.sort_by { |s| s.last_seen_at || Time.at(0) }.reverse
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
