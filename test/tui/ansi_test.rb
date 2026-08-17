# frozen_string_literal: true

require "test_helper"

class TuiAnsiTest < Minitest::Test
  A = Aiwatch::Tui::Ansi

  def test_strip_removes_sgr_codes
    assert_equal "hello", A.strip("\e[1;32mhello\e[0m")
  end

  def test_visible_length_ignores_ansi
    assert_equal 5, A.visible_length("\e[1;32mhello\e[0m")
  end

  def test_visible_length_of_plain_text
    assert_equal 11, A.visible_length("hello world")
  end

  def test_truncate_returns_text_unchanged_when_it_fits
    assert_equal "short", A.truncate("short", 20)
  end

  def test_truncate_plain_text_from_the_right
    assert_equal "hello w…", A.truncate("hello world", 8)
  end

  def test_truncate_visible_length_never_exceeds_max
    result = A.truncate("hello world", 8)
    assert_equal 8, A.visible_length(result)
  end

  def test_truncate_preserves_color_and_terminates_with_reset
    result = A.truncate("\e[1;32mhello world\e[0m", 8)
    assert_equal "\e[1;32mhello w…\e[0m", result
    assert_equal 8, A.visible_length(result)
  end

  def test_truncate_uncolored_text_adds_no_reset
    refute_includes A.truncate("hello world", 8), "\e[0m"
  end

  def test_truncate_from_left_keeps_the_tail
    result = A.truncate("/home/lucas/code/aiwatch/lib/foo.rb", 20, from: :left)
    assert_equal "…/aiwatch/lib/foo.rb", result
    assert_equal 20, A.visible_length(result)
  end

  def test_truncate_with_max_below_two_returns_original
    assert_equal "hello", A.truncate("hello", 1)
  end
end
