# frozen_string_literal: true

module Aiwatch
  module Live
    # Reads one key per call as either a one-character String (a
    # printable) or a Symbol (a named key: :up/:down/:left/:right/:home/
    # :end/:pgup/:pgdn/:enter/:esc/:backspace/:timeout/:quit/:unknown).
    # Keymap turns that into an action; nothing downstream of here parses
    # raw bytes or escape sequences.
    module Input
      ESCAPE_SEQUENCES = {
        "A" => :up, "B" => :down, "C" => :right, "D" => :left,
        "H" => :home, "F" => :end,
        "5~" => :pgup, "6~" => :pgdn
      }.freeze

      # Reads real keystrokes off a raw-mode terminal.
      class Terminal
        def initialize(in_stream: $stdin)
          @in = in_stream
        end

        def read_key(timeout)
          ready = IO.select([@in], nil, nil, timeout)
          return :timeout unless ready

          char = @in.getc
          return :timeout if char.nil?
          return read_escape if char == "\e"
          return :enter if char == "\r" || char == "\n"
          return :backspace if char == "" || char == "\b"

          char
        rescue IOError, Errno::EBADF, Errno::ENOTTY
          :quit
        end

        private

        # A bare Escape keypress sends just "\e" with nothing following;
        # an arrow/function key sends "\e[" plus more bytes. A short
        # follow-up select() distinguishes the two, same technique the
        # original single-view `live` used.
        def read_escape
          return :esc unless IO.select([@in], nil, nil, 0.05)
          return :unknown unless @in.getc == "["

          seq = read_sequence_tail
          ESCAPE_SEQUENCES[seq] || :unknown
        end

        # Reads up to 3 more bytes, stopping as soon as a terminating
        # letter/tilde arrives — enough for every sequence in
        # ESCAPE_SEQUENCES, including the 3-byte "\e[5~"/"\e[6~" forms.
        def read_sequence_tail
          seq = +""
          3.times do
            break unless IO.select([@in], nil, nil, 0.05)

            char = @in.getc
            break if char.nil?

            seq << char
            break if /[A-Za-z~]/.match?(char)
          end
          seq
        end
      end

      # Replays a fixed list of keys, then reports :quit — the test
      # double for Terminal.
      class Scripted
        def initialize(keys)
          @keys = keys.dup
        end

        def read_key(_timeout)
          @keys.empty? ? :quit : @keys.shift
        end
      end
    end
  end
end
