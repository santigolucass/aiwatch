# frozen_string_literal: true

module Aiwatch
  module Live
    module Widgets
      module TitleBar
        module_function

        def draw(canvas, rect, theme:, title:)
          inner = Tui::Box.draw(canvas, rect, theme: theme)
          text = theme.paint(title, :title, bold: true)
          col = inner.col + [(inner.width - title.length) / 2, 0].max
          canvas.write(inner.row, col, text, max: inner.width)
        end
      end
    end
  end
end
