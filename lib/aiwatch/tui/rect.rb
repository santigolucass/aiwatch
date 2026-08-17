# frozen_string_literal: true

module Aiwatch
  module Tui
    # A rectangular region of the screen: 0-based row/col, given width and
    # height. Every widget draws into a Rect handed to it by the layout —
    # nothing computes its own position.
    Rect = Struct.new(:row, :col, :width, :height) do
      def inset(n)
        Rect.new(row + n, col + n, [width - (2 * n), 0].max, [height - (2 * n), 0].max)
      end

      def empty?
        width <= 0 || height <= 0
      end

      # Splits vertically into consecutive rows. Each spec is either a
      # positive integer (a fixed row count) or :* (take all remaining
      # rows) — at most one :* is allowed, and it may be absent (leftover
      # rows are simply not covered by the returned Rects).
      def split_v(*specs)
        split(specs, height) { |offset, size| Rect.new(row + offset, col, width, size) }
      end

      # Splits horizontally into consecutive columns, same spec rules as
      # split_v.
      def split_h(*specs)
        split(specs, width) { |offset, size| Rect.new(row, col + offset, size, height) }
      end

      private

      def split(specs, total, &make)
        fixed = specs.reject { |s| s == :* }.sum
        star_count = specs.count { |s| s == :* }
        star_size = star_count.positive? ? [(total - fixed) / star_count, 0].max : 0

        offset = 0
        specs.map do |spec|
          size = (spec == :*) ? star_size : spec
          rect = make.call(offset, size)
          offset += size
          rect
        end
      end
    end
  end
end
