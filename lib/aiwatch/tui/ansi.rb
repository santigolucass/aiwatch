# frozen_string_literal: true

module Aiwatch
  module Tui
    # The single authority for ANSI SGR handling: stripping, measuring, and
    # truncating text that may carry color codes. Every other module that
    # needs to reason about "how many terminal columns does this string
    # occupy" goes through here, so there's exactly one regex to get right.
    #
    # Deliberately does NOT attempt to detect double-width Unicode glyphs —
    # see docs/decisions.md. Only single-column-safe glyphs (plain ASCII,
    # Braille, and glyphs explicitly marked safe in Theme) should go through
    # a column measured by this module.
    module Ansi
      SGR = /\e\[[0-9;]*m/
      SCAN = /(#{SGR})|(.)/m
      # Every C0 control byte except ESC (0x1B, needed for our own SGR
      # codes) and DEL. A literal newline/carriage-return/tab embedded
      # midway through a string is not a color code and not a printable
      # character either — writing it straight to the terminal moves the
      # real cursor (a bare "\n" moves it down a row even outside raw
      # mode; that's LF's own meaning, not the OPOST/ONLCR translation
      # the "\r\n" fix in docs/decisions.md addresses), corrupting
      # whatever the next Screen#flush row-write lands on. `#sanitize`
      # neutralizes this before any width/truncation math ever sees it.
      CONTROL_CHARS = /[\x00-\x1A\x1C-\x1F\x7F]/

      module_function

      def sanitize(text)
        text.to_s.gsub(CONTROL_CHARS, " ")
      end

      def strip(text)
        text.to_s.gsub(SGR, "")
      end

      def visible_length(text)
        strip(text).length
      end

      # Truncates by VISIBLE characters, preserving any ANSI codes that
      # appear before the cut point and always terminating with a reset so
      # a truncated colored cell can't bleed color into what follows.
      # from: :right (keep the start, "…" at the end) or :left (keep the
      # end, "…" at the start — for paths where the tail matters most).
      def truncate(text, max, from: :right)
        return text.to_s if visible_length(text) <= max || max < 2

        (from == :left) ? truncate_left(text, max) : truncate_right(text, max)
      end

      def truncate_right(text, max)
        budget = max - 1
        out = +""
        visible = 0
        done = false
        scan(text) do |code, char|
          next if done

          if code
            out << code
          elsif visible < budget
            out << char
            visible += 1
            done = true if visible == budget
          end
        end
        "#{out}…#{reset_if_colored(text)}"
      end

      def truncate_left(text, max)
        budget = max - 1
        chars = []
        codes = +""
        scan(text) do |code, char|
          code ? (codes << code) : chars.push(char)
        end
        tail = chars.last(budget).join
        "#{codes}…#{tail}#{reset_if_colored(text)}"
      end

      # Yields [code, nil] for each SGR escape encountered and [nil, char]
      # for each visible character, in order.
      def scan(text)
        text.to_s.scan(SCAN) do |code, char|
          code ? yield(code, nil) : yield(nil, char)
        end
      end

      def reset_if_colored(text)
        text.to_s.match?(SGR) ? "\e[0m" : ""
      end

      # Clips to exactly `max` visible characters with no ellipsis — the
      # safety net Canvas falls back to when a column is too narrow (0 or
      # 1 visible columns) for `truncate`'s ellipsis convention to apply.
      def hard_truncate(text, max)
        return "" if max <= 0

        out = +""
        visible = 0
        scan(text) do |code, char|
          break if visible >= max

          if code
            out << code
          else
            out << char
            visible += 1
          end
        end
        "#{out}#{reset_if_colored(text)}"
      end
    end
  end
end
