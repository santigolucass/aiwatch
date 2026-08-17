# frozen_string_literal: true

require "test_helper"

class LiveKeymapTest < Minitest::Test
  K = Aiwatch::Live::Keymap

  def test_browse_mode_maps_navigation_keys
    assert_equal :down, K.action_for("j", mode: :browse)
    assert_equal :up, K.action_for(:up, mode: :browse)
    assert_equal :kill, K.action_for("x", mode: :browse)
  end

  def test_confirm_mode_only_recognizes_yes_no_and_quit
    assert_equal :confirm, K.action_for("y", mode: :confirm)
    assert_equal :cancel, K.action_for("n", mode: :confirm)
    assert_nil K.action_for("x", mode: :confirm)
  end

  def test_input_mode_only_resolves_control_keys
    assert_equal :commit_input, K.action_for(:enter, mode: :input)
    assert_equal :cancel_input, K.action_for(:esc, mode: :input)
    assert_equal :backspace, K.action_for(:backspace, mode: :input)
    assert_nil K.action_for("a", mode: :input) # printable text, not an action
  end

  def test_help_overlay_falls_back_to_browse_actions_for_navigation
    assert_equal :cancel, K.action_for(:esc, mode: :help)
    assert_equal :down, K.action_for("j", mode: :help) # can still navigate under the overlay... falls back
  end

  def test_footer_text_includes_every_footer_group
    text = K.footer_text
    K::FOOTER_GROUPS.each { |key, label| assert_includes text, "#{key} #{label}" }
  end
end
