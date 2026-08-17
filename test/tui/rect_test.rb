# frozen_string_literal: true

require "test_helper"

class TuiRectTest < Minitest::Test
  Rect = Aiwatch::Tui::Rect

  def test_inset_shrinks_from_all_sides
    r = Rect.new(0, 0, 10, 6)
    inset = r.inset(1)
    assert_equal Rect.new(1, 1, 8, 4), inset
  end

  def test_inset_never_goes_negative
    r = Rect.new(0, 0, 1, 1)
    inset = r.inset(2)
    assert_equal 0, inset.width
    assert_equal 0, inset.height
  end

  def test_empty_when_width_or_height_non_positive
    assert Rect.new(0, 0, 0, 5).empty?
    assert Rect.new(0, 0, 5, 0).empty?
    refute Rect.new(0, 0, 5, 5).empty?
  end

  def test_split_v_with_fixed_sizes
    rects = Rect.new(0, 0, 20, 10).split_v(3, 3, 4)
    assert_equal [0, 3, 6], rects.map(&:row)
    assert_equal [3, 3, 4], rects.map(&:height)
    assert(rects.all? { |r| r.width == 20 && r.col == 0 })
  end

  def test_split_v_with_a_star_takes_remaining_space
    rects = Rect.new(0, 0, 20, 10).split_v(3, :*, 1)
    assert_equal [3, 6, 1], rects.map(&:height)
  end

  def test_split_h_with_fixed_and_star
    rects = Rect.new(5, 0, 100, 10).split_h(30, :*)
    assert_equal [30, 70], rects.map(&:width)
    assert_equal [0, 30], rects.map(&:col)
    assert(rects.all? { |r| r.row == 5 && r.height == 10 })
  end
end
