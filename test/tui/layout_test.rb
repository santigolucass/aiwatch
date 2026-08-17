# frozen_string_literal: true

require "test_helper"

class TuiLayoutTest < Minitest::Test
  Layout = Aiwatch::Tui::Layout

  def assert_consistent(regions, width, height)
    refute regions.too_small
    total_h = regions.title.height + regions.stats.height + regions.table.height +
      (regions.log&.height || 0) + regions.footer.height
    assert_equal height, total_h
    assert_equal width, regions.table.width + (regions.sidebar&.width || 0)
    assert_equal 0, regions.title.row
    assert_equal regions.title.height, regions.stats.row
  end

  def test_too_small_below_minimum_dimensions
    assert Layout.compute(59, 20).too_small
    assert Layout.compute(60, 19).too_small
  end

  def test_regions_are_internally_consistent_across_sizes
    [[60, 20], [80, 24], [90, 24], [120, 30], [200, 60]].each do |w, h|
      assert_consistent Layout.compute(w, h), w, h
    end
  end

  def test_sidebar_appears_only_when_there_is_room_for_both
    narrow = Layout.compute(80, 24)
    wide = Layout.compute(120, 30)
    assert_nil narrow.sidebar
    refute_nil wide.sidebar
    assert_operator wide.sidebar.width, :>=, Layout::SIDEBAR_MIN
    assert_operator wide.sidebar.width, :<=, Layout::SIDEBAR_MAX
  end

  def test_log_panel_height_is_clamped
    regions = Layout.compute(200, 60)
    assert_operator regions.log.height, :>=, 6
    assert_operator regions.log.height, :<=, 14
  end

  def test_no_region_overlaps_another_vertically
    regions = Layout.compute(120, 30)
    rows = [regions.title, regions.stats, regions.table, regions.log, regions.footer].compact
    rows.each_cons(2) { |a, b| assert_equal a.row + a.height, b.row }
  end
end
