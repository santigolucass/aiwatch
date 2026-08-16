# frozen_string_literal: true

require "io/console"

module Aiwatch
  module Renderers
    # Interactive, auto-refreshing view of currently-active sessions.
    # ↑/↓ move a selection cursor between sessions and expand a detail
    # panel (the same content as `aiwatch show`) above the table; x asks
    # for confirmation, then sends SIGTERM to the OS process that has the
    # selected session's log file open (found via ProcessFinder — Linux
    # only). Each session keeps its own stable sparkline color for the
    # life of the run, assigned in first-seen order from a small palette.
    #
    # Puts the terminal into raw mode so single keystrokes (arrows, x,
    # y/n, r, q, Ctrl-C) act instantly without waiting for Enter, and
    # always restores the terminal on the way out — including on an
    # unhandled exception.
    class Live
      REFRESH_SECONDS = 2
      SPARKLINE_WIDTH = 20 # Braille characters; each holds 2 samples
      PALETTE = [32, 36, 33, 35, 34, 31].freeze # green, cyan, yellow, magenta, blue, red
      # cursor, SESSION, NAME, PROJECT, MODEL(S), COST (USD), TOKENS/s, LAST ACTIVITY
      COLUMN_MAX_WIDTHS = [nil, nil, 32, 28, 24, nil, nil, nil].freeze

      KEY_EVENTS = {
        "q" => :quit, "\u0003" => :quit,
        "x" => :kill, "X" => :kill,
        "y" => :confirm, "Y" => :confirm,
        "n" => :cancel, "N" => :cancel,
        "r" => :refresh, "R" => :refresh
      }.freeze

      def initialize(adapter:, cost_calculator:, out: $stdout, in_stream: $stdin,
        active_threshold_minutes: 5, refresh_seconds: REFRESH_SECONDS, sparkline_width: SPARKLINE_WIDTH,
        clock: -> { Time.now }, read_event: nil,
        process_finder: ProcessFinder.method(:find_pid), killer: ->(pid, signal) { Process.kill(signal, pid) })
        @adapter = adapter
        @cost_calculator = cost_calculator
        @table = Table.new(cost_calculator)
        @out = out
        @in = in_stream
        @active_threshold_minutes = active_threshold_minutes
        @refresh_seconds = refresh_seconds
        @sparkline_width = sparkline_width
        @clock = clock
        @read_event = read_event || method(:terminal_read_event)
        @process_finder = process_finder
        @killer = killer

        @history = Hash.new { |h, k| h[k] = [] }
        @previous_totals = {}
        @session_colors = {}
        @sessions = []
        @selected_id = nil
        @mode = :browse
        @pending_kill_id = nil
        @status_message = nil
        @killed_ids = {}
      end

      def run
        setup_terminal
        now = @clock.call
        refresh(now)
        render_once(now)
        loop do
          event = @read_event.call(@refresh_seconds)
          now = @clock.call
          case event
          when :timeout, :refresh then refresh(now)
          when :quit then break
          else apply_event(event, now)
          end
          render_once(now)
        end
      ensure
        restore_terminal
      end

      private

      def refresh(now)
        @sessions = active_sessions(now)
        record_tick(@sessions)
        sync_selection
      end

      def sync_selection
        if @sessions.empty?
          @selected_id = nil
        elsif @sessions.none? { |s| s.id == @selected_id }
          @selected_id = @sessions.first.id
        end
      end

      def apply_event(event, now)
        if @mode == :confirm_kill
          case event
          when :confirm then confirm_kill(now)
          when :cancel then cancel_kill
          end
          return
        end

        case event
        when :up then move_selection(-1)
        when :down then move_selection(1)
        when :kill then start_kill
        end
      end

      def move_selection(delta)
        return if @sessions.empty?

        index = @sessions.index { |s| s.id == @selected_id } || 0
        @selected_id = @sessions[(index + delta).clamp(0, @sessions.length - 1)].id
        @status_message = nil
      end

      def start_kill
        return if @selected_id.nil?

        @pending_kill_id = @selected_id
        @mode = :confirm_kill
      end

      def cancel_kill
        @pending_kill_id = nil
        @mode = :browse
      end

      def confirm_kill(now)
        session = @sessions.find { |s| s.id == @pending_kill_id }
        @mode = :browse
        @pending_kill_id = nil
        return unless session

        pid = @process_finder.call(session.file_path)
        if pid
          @killer.call(pid, "TERM")
          # active? is based on the log file's mtime, which killing the
          # process doesn't touch — it would otherwise keep showing as
          # active until that naturally expires (active_threshold_minutes,
          # up to several minutes). Suppress it locally instead.
          @killed_ids[session.id] = true
          @status_message = "Sent SIGTERM to process #{pid} (session #{session.short_id})."
        else
          @status_message = "Could not find a running process for session #{session.short_id}."
        end
        refresh(now)
      rescue Errno::ESRCH
        @status_message = "Process for session #{session.short_id} was already gone."
        refresh(now)
      end

      def render_once(now)
        @out.print "\e[H\e[2J"
        write_line "aiwatch live — #{now.strftime("%H:%M:%S")} — #{@sessions.length} active session(s)"
        write_line
        if @sessions.empty?
          write_line "(no active sessions)"
        else
          detail_panel(now).each_line(chomp: true) { |line| write_line(line) }
          write_line
          session_table(now).each_line(chomp: true) { |line| write_line(line) }
        end
        write_line
        write_line footer
        @out.flush if @out.respond_to?(:flush)
      end

      def detail_panel(now)
        session = @sessions.find { |s| s.id == @selected_id }
        session ? @table.render_show(session, now: now) : ""
      end

      def footer
        return "Kill session #{pending_kill_short_id}? y = confirm, n/Esc = cancel" if @mode == :confirm_kill

        @status_message || "↑/↓ select session   x kill selected session   r refresh   q quit"
      end

      def pending_kill_short_id
        @sessions.find { |s| s.id == @pending_kill_id }&.short_id
      end

      # setup_terminal puts the tty into raw mode, which disables the
      # terminal's own \n -> \r\n translation (OPOST/ONLCR) for the whole
      # device (stdin and stdout share one tty) — not just for stdin
      # reads. A plain #puts (bare "\n") then moves the cursor down a row
      # without returning to column 0, so each line starts wherever the
      # previous one ended, cascading further right every frame. Writing
      # "\r\n" ourselves sidesteps relying on that translation entirely.
      def write_line(text = "")
        @out.print "#{text}\r\n"
      end

      def active_sessions(now)
        sessions = @adapter.discover_sessions.select do |s|
          s.active?(now: now, threshold_minutes: @active_threshold_minutes) && !@killed_ids.key?(s.id)
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

      def session_table(now)
        color = @out.respond_to?(:tty?) && @out.tty?
        headers = ["", "SESSION", "NAME", "PROJECT", "MODEL(S)", "COST (USD)", "TOKENS/s (#{window_label})", "LAST ACTIVITY"]
        rows = @sessions.map { |s| session_row(s, now, color) }
        aligns = [:left, :left, :left, :left, :left, :right, :left, :left]
        TextTable.render(headers, rows, aligns, max_widths: COLUMN_MAX_WIDTHS)
      end

      def session_row(session, now, color)
        total = @cost_calculator.total_for(session)
        ansi = @session_colors[session.id]
        sparkline = BrailleSparkline.render(@history[session.id], width: @sparkline_width)
        [
          (session.id == @selected_id) ? ">" : " ",
          colorize(session.short_id, ansi, color, bold: true),
          session.title || "?",
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

      def terminal_read_event(timeout)
        ready = IO.select([@in], nil, nil, timeout)
        return :timeout unless ready

        char = @in.getc
        return :timeout if char.nil?
        return read_escape_sequence if char == "\e"

        KEY_EVENTS[char] || :unknown
      rescue IOError, Errno::EBADF, Errno::ENOTTY
        :quit
      end

      # Arrow keys arrive as a 3-byte escape sequence ("\e[A" for up,
      # "\e[B" for down). A bare Escape keypress sends just "\e" with
      # nothing following, so a short follow-up select() distinguishes
      # "arrow sequence incoming" from "the user pressed Escape" (treated
      # as cancel, harmless when nothing is pending confirmation).
      def read_escape_sequence
        return :cancel unless IO.select([@in], nil, nil, 0.05)

        second = @in.getc
        return :cancel unless second == "["
        return :unknown unless IO.select([@in], nil, nil, 0.05)

        case @in.getc
        when "A" then :up
        when "B" then :down
        else :unknown
        end
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
