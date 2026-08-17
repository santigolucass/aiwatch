# frozen_string_literal: true

require "test_helper"

class TuiCanvasTest < Minitest::Test
  Canvas = Aiwatch::Tui::Canvas
  Rect = Aiwatch::Tui::Rect

  def test_to_lines_returns_exactly_height_lines_of_exactly_width
    canvas = Canvas.new(width: 10, height: 3)
    lines = canvas.to_lines
    assert_equal 3, lines.length
    assert(lines.all? { |l| l.length == 10 })
  end

  def test_blank_canvas_is_all_spaces
    canvas = Canvas.new(width: 5, height: 1)
    assert_equal " " * 5, canvas.to_lines.first
  end

  def test_write_places_text_at_the_given_column
    canvas = Canvas.new(width: 10, height: 1)
    canvas.write(0, 2, "hi")
    assert_equal "  hi      ", canvas.to_lines.first
  end

  def test_write_clips_at_the_canvas_edge
    canvas = Canvas.new(width: 10, height: 1)
    canvas.write(0, 8, "toolong")
    line = canvas.to_lines.first
    assert_equal 10, line.length
  end

  def test_write_respects_an_explicit_max
    canvas = Canvas.new(width: 20, height: 1)
    canvas.write(0, 0, "hello world", max: 5)
    line = canvas.to_lines.first
    assert_equal "hello world"[0, 4] + "…", line[0, 5]
  end

  def test_write_out_of_bounds_is_a_silent_noop
    canvas = Canvas.new(width: 5, height: 1)
    canvas.write(5, 0, "x")
    canvas.write(0, 5, "x")
    canvas.write(-1, 0, "x")
    assert_equal " " * 5, canvas.to_lines.first
  end

  def test_later_write_overwrites_only_the_columns_it_touches
    canvas = Canvas.new(width: 10, height: 1)
    canvas.write(0, 0, "aaaaaaaaaa")
    canvas.write(0, 3, "XX")
    assert_equal "aaaXXaaaa", canvas.to_lines.first[0, 9]
  end

  def test_colored_write_survives_a_full_round_trip
    canvas = Canvas.new(width: 10, height: 1)
    canvas.write(0, 0, "\e[1;32mhi\e[0m")
    line = canvas.to_lines.first
    assert_equal 10, Aiwatch::Tui::Ansi.visible_length(line)
    assert_includes line, "\e[1;32m"
  end

  def test_truncated_colored_write_does_not_bleed_color_into_later_text
    canvas = Canvas.new(width: 10, height: 1)
    canvas.write(0, 0, "\e[1;32mhello world\e[0m", max: 5)
    canvas.write(0, 5, "plain")
    line = canvas.to_lines.first
    # once the colored span ends there must be a reset before "plain"
    assert_match(/\e\[0m.*plain\z/, line)
  end

  def test_embedded_newline_does_not_move_the_cursor_or_corrupt_adjacent_rows
    canvas = Canvas.new(width: 20, height: 3)
    canvas.write(1, 0, "before\nafter this line")
    lines = canvas.to_lines
    assert_equal 3, lines.length
    assert(lines.all? { |l| l.length == 20 })
    # the embedded newline must not have pushed content onto row 2 or 0
    refute_includes lines[0], "after"
    refute_includes lines[2], "after"
    assert_includes lines[1], "before"
  end

  def test_embedded_carriage_return_and_tab_are_neutralized
    canvas = Canvas.new(width: 10, height: 1)
    canvas.write(0, 0, "a\r\tb")
    line = canvas.to_lines.first
    assert_equal 10, line.length
    refute_includes line, "\r"
    refute_includes line, "\t"
  end

  def test_fill_paints_a_rect_with_a_repeated_cell
    canvas = Canvas.new(width: 6, height: 3)
    canvas.fill(Rect.new(1, 1, 4, 1), "#")
    assert_equal " " * 6, canvas.to_lines[0]
    assert_equal " #### ", canvas.to_lines[1]
    assert_equal " " * 6, canvas.to_lines[2]
  end

  def test_fill_clips_to_canvas_bounds
    canvas = Canvas.new(width: 6, height: 2)
    canvas.fill(Rect.new(-1, -1, 10, 10), "#")
    assert(canvas.to_lines.all? { |l| l.length == 6 })
    assert_equal "#" * 6, canvas.to_lines[0]
  end
end
