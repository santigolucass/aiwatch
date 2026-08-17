# frozen_string_literal: true

require "io/console"

module Aiwatch
  module Tui
    # Owns everything that talks to the actual terminal: raw mode, the
    # alternate screen buffer, cursor visibility, size detection, resize
    # notification, and painting frames. The only object in the dashboard
    # that writes to `out`.
    #
    # Frames are painted with absolute per-row cursor positioning
    # (`\e[<row>;1H`) rather than newlines, which structurally sidesteps
    # the raw-mode ONLCR problem that caused a real `\r\n` cascade bug in
    # this project's first `live` implementation (see docs/decisions.md):
    # there is no bare "\n" anywhere in this class for a terminal's own
    # newline translation to mishandle.
    class Screen
      DEFAULT_SIZE = [80, 24].freeze # [columns, lines]

      def initialize(out: $stdout, in_stream: $stdin, size_reader: nil, diff: true, altscreen: true, env: ENV)
        @out = out
        @in = in_stream
        @size_reader = size_reader || method(:winsize_reader)
        @diff = diff
        @altscreen = altscreen
        @env = env
        @previous_lines = nil
        @resized = false
        @winch_installed = false
        @previous_winch_handler = nil
      end

      def tty?
        @out.respond_to?(:tty?) && @out.tty?
      end

      # winsize (a real tty) first, then $COLUMNS/$LINES (set by many
      # terminal multiplexers and shells even when stdout is redirected),
      # then a hardcoded 80x24 as the last resort.
      def size
        cols, lines = @size_reader.call
        cols ||= env_int("COLUMNS")
        lines ||= env_int("LINES")
        [cols || DEFAULT_SIZE[0], lines || DEFAULT_SIZE[1]]
      rescue Errno::ENOTTY, IOError, NoMethodError
        [env_int("COLUMNS") || DEFAULT_SIZE[0], env_int("LINES") || DEFAULT_SIZE[1]]
      end

      def enter
        @in.raw! if @in.respond_to?(:raw!)
        @out.print "\e[?1049h" if use_altscreen?
        @out.print "\e[?25l"
        install_winch_trap
      rescue IOError, Errno::ENOTTY
        nil
      end

      def exit
        @out.print "\e[?25h"
        @out.print "\e[?1049l" if use_altscreen?
        @in.cooked! if @in.respond_to?(:cooked!)
        restore_winch_trap
      rescue IOError, Errno::ENOTTY
        nil
      end

      # True at most once per resize; consumes the flag so the caller
      # naturally forces a full redraw only on the frame after a resize.
      def resized?
        return false unless @resized

        @resized = false
        true
      end

      # lines: Array<String>, Canvas#to_lines' output — one already
      # terminal-width-clipped string per row. Repaints only rows that
      # changed since the previous frame, unless forced (first frame,
      # after a resize, or diffing disabled).
      # Writes raw bytes straight to the terminal, bypassing row
      # positioning — for out-of-band escape sequences (an OSC 52
      # clipboard write) that aren't part of any row's visible content.
      def write_raw(text)
        @out.print text
        @out.flush if @out.respond_to?(:flush)
      end

      def flush(lines, force: false)
        if force || !@diff || @previous_lines.nil?
          lines.each_with_index { |line, i| paint_row(i, line) }
        else
          lines.each_with_index { |line, i| paint_row(i, line) if line != @previous_lines[i] }
        end
        @out.flush if @out.respond_to?(:flush)
        @previous_lines = lines
      end

      private

      def use_altscreen?
        @altscreen && tty?
      end

      def paint_row(index, line)
        @out.print "\e[#{index + 1};1H\e[K#{line}"
      end

      def env_int(name)
        value = @env[name]
        return nil unless value

        Integer(value, exception: false)
      end

      def winsize_reader
        return [nil, nil] unless @out.respond_to?(:winsize)

        lines, cols = @out.winsize
        [cols, lines]
      end

      def install_winch_trap
        return unless Signal.list.key?("WINCH")

        @previous_winch_handler = Signal.trap("WINCH") { @resized = true }
        @winch_installed = true
      rescue ArgumentError
        nil
      end

      def restore_winch_trap
        return unless @winch_installed

        Signal.trap("WINCH", @previous_winch_handler || "DEFAULT")
        @winch_installed = false
      rescue ArgumentError
        nil
      end
    end
  end
end
