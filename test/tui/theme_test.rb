# frozen_string_literal: true

require "test_helper"

class TuiThemeTest < Minitest::Test
  def test_detect_returns_none_when_not_a_tty
    out = StringIO.new
    def out.tty? = false

    assert_equal :none, Aiwatch::Tui::Theme.detect(out: out, env: {})
  end

  def test_detect_respects_no_color
    out = StringIO.new
    def out.tty? = true

    assert_equal :none, Aiwatch::Tui::Theme.detect(out: out, env: {"NO_COLOR" => "1"})
  end

  def test_detect_respects_term_dumb
    out = StringIO.new
    def out.tty? = true

    assert_equal :none, Aiwatch::Tui::Theme.detect(out: out, env: {"TERM" => "dumb"})
  end

  def test_detect_picks_ansi256_for_256color_term
    out = StringIO.new
    def out.tty? = true

    assert_equal :ansi256, Aiwatch::Tui::Theme.detect(out: out, env: {"TERM" => "xterm-256color"})
  end

  def test_detect_falls_back_to_ansi16
    out = StringIO.new
    def out.tty? = true

    assert_equal :ansi16, Aiwatch::Tui::Theme.detect(out: out, env: {"TERM" => "xterm"})
  end

  def test_paint_wraps_with_sgr_and_reset
    theme = Aiwatch::Tui::Theme.new(depth: :ansi16)
    assert_equal "\e[1;32mfoo\e[0m", theme.paint("foo", :active, bold: true)
  end

  def test_paint_at_ansi256_depth_uses_the_extended_color_escape
    theme = Aiwatch::Tui::Theme.new(depth: :ansi256)
    result = theme.paint("foo", :active, bold: true)
    assert_equal "\e[1;38;5;82mfoo\e[0m", result
  end

  def test_paint_session_at_ansi256_depth_uses_the_extended_color_escape
    theme = Aiwatch::Tui::Theme.new(depth: :ansi256)
    result = theme.paint_session("foo", 0)
    assert_match(/\A\e\[38;5;\d+mfoo\e\[0m\z/, result)
  end

  def test_paint_is_a_noop_when_depth_is_none
    theme = Aiwatch::Tui::Theme.new(depth: :none)
    assert_equal "foo", theme.paint("foo", :active, bold: true)
  end

  def test_unknown_role_paints_plain
    theme = Aiwatch::Tui::Theme.new(depth: :ansi256)
    assert_equal "foo", theme.paint("foo", :nonexistent_role)
  end

  def test_session_color_is_stable_and_cycles
    theme = Aiwatch::Tui::Theme.new(depth: :ansi16)
    first = theme.session_color(0)
    assert_equal first, theme.session_color(Aiwatch::Tui::Theme::SESSION_PALETTE.length)
  end

  def test_paint_session_distinct_colors_for_distinct_indices
    theme = Aiwatch::Tui::Theme.new(depth: :ansi16)
    a = theme.paint_session("a", 0, bold: true)
    b = theme.paint_session("b", 1, bold: true)
    refute_equal a[/\e\[1;(\d+)m/, 1], b[/\e\[1;(\d+)m/, 1]
  end

  def test_ascii_mode_swaps_glyphs
    unicode = Aiwatch::Tui::Theme.new(ascii: false)
    ascii = Aiwatch::Tui::Theme.new(ascii: true)
    refute_equal unicode.glyph(:active_dot), ascii.glyph(:active_dot)
    assert_equal ">", ascii.glyph(:cursor)
  end

  def test_with_preset_returns_a_new_instance_with_only_the_preset_changed
    theme = Aiwatch::Tui::Theme.new(depth: :ansi16, preset: :purple, ascii: true)
    other = theme.with_preset(:matrix)
    assert_equal :matrix, other.preset
    assert_equal :ansi16, other.depth
    assert other.ascii
    assert_equal :purple, theme.preset # original untouched
  end

  def test_next_preset_cycles_through_all_presets
    theme = Aiwatch::Tui::Theme.new(preset: :purple)
    seen = [theme.preset]
    3.times { seen << (theme = Aiwatch::Tui::Theme.new(preset: theme.next_preset)).preset }
    assert_equal Aiwatch::Tui::Theme::PRESETS.keys.length, seen.uniq.length
  end
end
