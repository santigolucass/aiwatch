# frozen_string_literal: true

require "test_helper"

class TuiBoxTest < Minitest::Test
  Canvas = Aiwatch::Tui::Canvas
  Rect = Aiwatch::Tui::Rect
  Box = Aiwatch::Tui::Box
  Theme = Aiwatch::Tui::Theme

  def theme
    Theme.new(depth: :none)
  end

  def test_draws_a_border_and_returns_the_inset_interior
    canvas = Canvas.new(width: 10, height: 5)
    inner = Box.draw(canvas, Rect.new(0, 0, 10, 5), theme: theme)
    assert_equal Rect.new(1, 1, 8, 3), inner

    lines = canvas.to_lines
    assert_equal "┌────────┐", lines[0]
    assert_equal "│        │", lines[1]
    assert_equal "└────────┘", lines[4]
  end

  def test_title_is_painted_over_the_top_border_without_breaking_width
    canvas = Canvas.new(width: 30, height: 4)
    Box.draw(canvas, Rect.new(0, 0, 30, 4), theme: theme, title: "Session Detail")
    top = canvas.to_lines[0]
    assert_equal 30, top.length
    assert_includes top, "Session Detail"
    assert top.start_with?("┌")
    assert top.end_with?("┐")
  end

  def test_long_title_is_truncated_rather_than_overflowing
    canvas = Canvas.new(width: 12, height: 3)
    Box.draw(canvas, Rect.new(0, 0, 12, 3), theme: theme, title: "A Much Too Long Title")
    top = canvas.to_lines[0]
    assert_equal 12, top.length
  end

  def test_too_small_a_rect_does_not_raise
    canvas = Canvas.new(width: 5, height: 5)
    result = Box.draw(canvas, Rect.new(0, 0, 1, 1), theme: theme)
    assert_equal Rect.new(0, 0, 1, 1), result
  end
end
