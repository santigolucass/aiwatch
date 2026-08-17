# frozen_string_literal: true

module Aiwatch
  module Live
    module Views
      # Full-screen key reference, generated from the same
      # Keymap::FOOTER_GROUPS table the footer line uses — plus the
      # handful of keys that only apply mid-flow (confirm/input modes),
      # which never fit in the one-line footer.
      module Help
        MODE_KEYS = [
          ["y / n", "Confirm / cancel a pending kill"],
          ["Enter", "Confirm text entry (filter, search, export path, kill-all)"],
          ["Esc", "Cancel text entry, or return to the dashboard from another view"]
        ].freeze

        module_function

        def draw(canvas, regions, theme:)
          rect = Tui::Rect.new(0, 0, canvas.width, canvas.height - 1)
          inner = Tui::Box.draw(canvas, rect, theme: theme, title: "Help — press Esc or ? to close")
          return if inner.empty?

          row = inner.row
          row = write_section(canvas, inner, row, theme, "Keys", Keymap::FOOTER_GROUPS)
          write_section(canvas, inner, row + 1, theme, "While confirming or typing", MODE_KEYS)
        end

        def write_section(canvas, inner, start_row, theme, heading, pairs)
          canvas.write(start_row, inner.col, theme.paint(heading, :header, bold: true), max: inner.width)
          row = start_row + 1
          pairs.each do |key, label|
            break if row >= inner.row + inner.height

            line = "  #{key.to_s.ljust(8)} #{label}"
            canvas.write(row, inner.col, line, max: inner.width)
            row += 1
          end
          row
        end
      end
    end
  end
end
