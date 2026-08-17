# frozen_string_literal: true

module Aiwatch
  module Live
    module Widgets
      module Footer
        module_function

        def draw(canvas, rect, theme:, text:)
          canvas.write(rect.row, rect.col, theme.paint(text, :muted), max: rect.width)
        end
      end
    end
  end
end
