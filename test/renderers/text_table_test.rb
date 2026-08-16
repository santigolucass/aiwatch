# frozen_string_literal: true

require_relative "../test_helper"

class RenderersTextTableTest < Minitest::Test
  def test_pads_columns_to_the_widest_cell
    out = Aiwatch::Renderers::TextTable.render(["A", "BB"], [["x", "yy"], ["longvalue", "z"]])
    lines = out.lines.map(&:rstrip)

    assert_equal "A          BB", lines[0]
    assert_equal "x          yy", lines[1]
    assert_equal "longvalue  z", lines[2]
  end

  def test_right_align
    out = Aiwatch::Renderers::TextTable.render(["N"], [["1"], ["100"]], [:right])
    lines = out.lines.map(&:rstrip)

    # Headers stay left-aligned by convention even over a right-aligned
    # numeric column (matches ls -l / ps style tables).
    assert_equal "N", lines[0]
    assert_equal "  1", lines[1]
    assert_equal "100", lines[2]
  end

  def test_ansi_color_codes_do_not_affect_column_width
    colored = "\e[1;32mfoo\e[0m"
    out = Aiwatch::Renderers::TextTable.render(["ID", "NEXT"], [[colored, "x"], ["bar", "y"]])
    lines = out.lines.map(&:rstrip)

    # "foo" and "bar" are both 3 visible chars, so NEXT must start at the
    # same VISIBLE column on both rows despite the ANSI codes around "foo"
    # inflating row 1's raw byte length.
    visible_column_of = ->(line, char) { Aiwatch::Renderers::TextTable.visible_length(line[0...line.index(char)]) }
    assert_equal visible_column_of.call(lines[2], "y"), visible_column_of.call(lines[1], "x")
  end

  def test_visible_length_strips_ansi
    assert_equal 3, Aiwatch::Renderers::TextTable.visible_length("\e[32mfoo\e[0m")
    assert_equal 0, Aiwatch::Renderers::TextTable.visible_length("")
  end

  def test_max_widths_truncates_long_cells_with_ellipsis_and_caps_the_column
    long_path = "/home/someone/a/very/long/nested/project/directory/path"
    out = Aiwatch::Renderers::TextTable.render(
      ["ID", "PROJECT"], [["x", long_path], ["y", "/short"]], nil, max_widths: [nil, 20]
    )
    lines = out.lines.map(&:rstrip)

    assert(lines.all? { |l| l.length <= "ID  ".length + 20 })
    assert_includes lines[1], "…"
    refute_includes lines[1], long_path
  end

  def test_max_widths_leaves_short_cells_and_other_columns_untouched
    out = Aiwatch::Renderers::TextTable.render(["ID", "PROJECT"], [["x", "/short"]], nil, max_widths: [nil, 20])

    assert_includes out, "/short"
    refute_includes out, "…"
  end
end
