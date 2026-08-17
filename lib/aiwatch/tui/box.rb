# frozen_string_literal: true

require_relative "ansi"

module Aiwatch
  module Tui
    # Draws a bordered rectangle with an optional title into a Canvas, and
    # returns the inset Rect of its interior for the caller to draw into.
    module Box
      module_function

      def draw(canvas, rect, theme:, title: nil)
        return rect if rect.width < 2 || rect.height < 2

        paint = ->(text) { theme.paint(text, :border) }
        v = paint.call(theme.glyph(:box_v))

        canvas.write(rect.row, rect.col, paint.call(top_line(rect, theme)))
        canvas.write(rect.row + rect.height - 1, rect.col, paint.call(bottom_line(rect, theme)))
        (rect.row + 1...(rect.row + rect.height - 1)).each do |r|
          canvas.write(r, rect.col, v)
          canvas.write(r, rect.col + rect.width - 1, v)
        end
        draw_title(canvas, rect, theme, title) if title
        rect.inset(1)
      end

      def top_line(rect, theme)
        theme.glyph(:box_tl) + (theme.glyph(:box_h) * (rect.width - 2)) + theme.glyph(:box_tr)
      end
      private_class_method :top_line

      def bottom_line(rect, theme)
        theme.glyph(:box_bl) + (theme.glyph(:box_h) * (rect.width - 2)) + theme.glyph(:box_br)
      end
      private_class_method :bottom_line

      def draw_title(canvas, rect, theme, title)
        budget = rect.width - 4
        return unless budget.positive?

        label = " #{title} "
        label = Ansi.truncate(label, budget) if Ansi.visible_length(label) > budget
        canvas.write(rect.row, rect.col + 2, theme.paint(label, :title, bold: true), max: budget)
      end
      private_class_method :draw_title
    end
  end
end
