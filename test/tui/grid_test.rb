# frozen_string_literal: true

require "test_helper"

class TuiGridTest < Minitest::Test
  Grid = Aiwatch::Tui::Grid
  Theme = Aiwatch::Tui::Theme

  def dashboard_columns
    [
      {key: :cursor, width: 1, priority: 0},
      {key: :pid, header: "PID", min: 5, max: 7, align: :right, priority: 1},
      {key: :status, header: "STATUS", min: 6, max: 8, priority: 1},
      {key: :ctx, header: "CTX", min: 5, max: 9, align: :right, priority: 1},
      {key: :title, header: "TITLE", min: 10, max: 60, weight: 3, priority: 2},
      {key: :cost, header: "COST", min: 6, max: 9, align: :right, priority: 3},
      {key: :cpu, header: "CPU%", min: 5, max: 6, align: :right, priority: 3},
      {key: :mem, header: "MEM%", min: 5, max: 6, align: :right, priority: 3},
      {key: :started, header: "STARTED", min: 5, max: 8, priority: 4},
      {key: :branch, header: "BRANCH", min: 6, max: 18, weight: 1, priority: 5},
      {key: :model, header: "MODEL", min: 6, max: 16, weight: 1, priority: 6},
      {key: :dir, header: "DIRECTORY", min: 10, max: 40, weight: 2, priority: 7, truncate_from: :left},
      {key: :cpuhist, header: "CPU-HIST", width: 10, priority: 8}
    ]
  end

  def theme
    Theme.new(depth: :none)
  end

  def sample_values
    {
      cursor: ">", pid: "11340", status: "ACTIVE", ctx: "40%",
      title: "Base directory for this skill: /home/lucas/code/fluxo/.claude/skills/epico",
      cost: "$0.21", cpu: "1.6", mem: "1.1", started: "16h",
      branch: "feat/kan-141-meetings-api-and-web-and-more", model: "fable-5",
      dir: "/home/lucas/code/fluxo/.claude/worktrees/kan-141-meetings-api",
      cpuhist: "xxxxxxxxxx"
    }
  end

  def test_never_overflows_across_a_wide_range_of_widths
    grid = Grid.new(dashboard_columns)
    (60..200).each do |w|
      cols = grid.layout(w)
      header = grid.render_header(cols, theme: theme)
      row = grid.render_row(cols, sample_values)
      assert_operator grid.used_width(cols), :<=, w, "used_width overflowed at #{w}"
      assert_operator header.length, :<=, w, "header overflowed at #{w}"
      assert_operator row.length, :<=, w, "row overflowed at #{w}"
    end
  end

  def test_essential_columns_are_never_dropped
    grid = Grid.new(dashboard_columns)
    cols = grid.layout(60)
    keys = cols.map(&:key)
    assert_includes keys, :cursor
    assert_includes keys, :pid
    assert_includes keys, :status
    assert_includes keys, :ctx
    assert_includes keys, :title
  end

  def test_low_priority_columns_drop_first_as_width_shrinks
    grid = Grid.new(dashboard_columns)
    wide = grid.layout(200).map(&:key)
    narrow = grid.layout(65).map(&:key)
    assert_includes wide, :cpuhist
    refute_includes narrow, :cpuhist
  end

  def test_surplus_width_grows_weighted_columns
    grid = Grid.new([
      {key: :fixed, header: "F", min: 5, max: 5, priority: 1},
      {key: :flex, header: "FLEX", min: 5, max: 50, weight: 1, priority: 2}
    ])
    cols = grid.layout(30)
    flex = cols.find { |c| c.key == :flex }
    assert_operator flex.width, :>, 5
  end

  def test_weighted_columns_never_exceed_their_max
    grid = Grid.new([
      {key: :flex, header: "FLEX", min: 5, max: 10, weight: 1, priority: 1}
    ])
    cols = grid.layout(200)
    assert_equal 10, cols.first.width
  end

  def test_render_row_pads_and_aligns
    grid = Grid.new([
      {key: :a, header: "A", min: 5, align: :left, priority: 1},
      {key: :b, header: "B", min: 5, align: :right, priority: 1}
    ])
    cols = grid.layout(11) # exactly min + min + 1 gap, no surplus to distribute
    row = grid.render_row(cols, {a: "x", b: "y"})
    assert_equal "x         y", row
  end
end
