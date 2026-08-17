# frozen_string_literal: true

require "test_helper"

class LiveStateTest < Minitest::Test
  FakeSession = Struct.new(:id, :title, :project, :branch, :dead, :last_seen_at, :first_seen_at) do
    def dead?
      dead
    end
  end

  def session(id, title: "t", project: nil, branch: nil, dead: false, last_seen_at: Time.now, first_seen_at: Time.now)
    FakeSession.new(id, title, project, branch, dead, last_seen_at, first_seen_at)
  end

  def state
    Aiwatch::Live::State.new
  end

  # --- pin ---

  def test_pin_toggles
    s = state
    refute s.pinned?("a")
    s.toggle_pin("a")
    assert s.pinned?("a")
    s.toggle_pin("a")
    refute s.pinned?("a")
  end

  def test_pinned_sessions_sort_first_regardless_of_other_sort_order
    s = state
    a = session("a", last_seen_at: Time.now - 100)
    b = session("b", last_seen_at: Time.now)
    s.toggle_pin("a")
    visible = s.visible([a, b])
    assert_equal %w[a b], visible.map(&:id)
  end

  # --- purge ---

  def test_purge_removes_a_session_from_visible_permanently
    s = state
    a = session("a", dead: true)
    b = session("b")
    s.purge("a")
    assert_equal ["b"], s.visible([a, b]).map(&:id)
  end

  def test_purge_all_dead_only_purges_dead_sessions
    s = state
    a = session("a", dead: true)
    b = session("b", dead: false)
    s.purge_all_dead([a, b])
    assert_equal ["b"], s.visible([a, b]).map(&:id)
  end

  # --- show_dead ---

  def test_show_dead_false_hides_dead_sessions
    s = state
    s.show_dead = false
    a = session("a", dead: true)
    b = session("b", dead: false)
    assert_equal ["b"], s.visible([a, b]).map(&:id)
  end

  # --- filter ---

  def test_filter_matches_title_project_or_branch_case_insensitively
    s = state
    a = session("a", title: "Fix the LOGIN bug")
    b = session("b", title: "Unrelated")
    s.filter_text = "login"
    assert_equal ["a"], s.visible([a, b]).map(&:id)
  end

  def test_empty_filter_matches_everything
    s = state
    a = session("a")
    b = session("b")
    s.filter_text = ""
    assert_equal 2, s.visible([a, b]).length
  end

  # --- sort ---

  def test_cycle_sort_advances_through_all_keys_and_wraps
    s = state
    keys = [s.sort_key]
    Aiwatch::Live::State::SORT_KEYS.length.times {
      s.cycle_sort
      keys << s.sort_key
    }
    assert_equal Aiwatch::Live::State::SORT_KEYS.length + 1, keys.length
    assert_equal keys.first, keys.last # wrapped back to the start
  end

  def test_default_sort_is_last_activity_descending
    s = state
    a = session("a", last_seen_at: Time.now - 100)
    b = session("b", last_seen_at: Time.now)
    assert_equal %w[b a], s.visible([a, b]).map(&:id)
  end

  def test_sort_by_cost_uses_the_injected_lookup
    s = state
    s.sort_key = :cost
    a = session("a")
    b = session("b")
    costs = {"a" => 1.0, "b" => 5.0}
    result = s.visible([a, b], cost_for: ->(sess) { costs[sess.id] })
    assert_equal %w[b a], result.map(&:id)
  end

  def test_sort_by_name_is_alphabetical
    s = state
    s.sort_key = :name
    a = session("a", title: "Zebra")
    b = session("b", title: "Apple")
    assert_equal %w[b a], s.visible([a, b]).map(&:id)
  end

  def test_sort_by_started_is_earliest_first
    s = state
    s.sort_key = :started
    a = session("a", first_seen_at: Time.now)
    b = session("b", first_seen_at: Time.now - 100)
    assert_equal %w[b a], s.visible([a, b]).map(&:id)
  end

  # --- selection ---

  def test_sync_selection_falls_back_to_first_when_selection_disappears
    s = state
    s.selected_id = "gone"
    s.sync_selection([session("a"), session("b")])
    assert_equal "a", s.selected_id
  end

  def test_sync_selection_is_nil_when_nothing_visible
    s = state
    s.selected_id = "a"
    s.sync_selection([])
    assert_nil s.selected_id
  end

  def test_sync_selection_keeps_a_still_present_selection
    s = state
    s.selected_id = "b"
    s.sync_selection([session("a"), session("b")])
    assert_equal "b", s.selected_id
  end

  def test_move_selection_clamps_at_the_edges
    s = state
    visible = [session("a"), session("b")]
    s.selected_id = "a"
    s.move_selection(visible, -1)
    assert_equal "a", s.selected_id
    s.move_selection(visible, 1)
    assert_equal "b", s.selected_id
    s.move_selection(visible, 1)
    assert_equal "b", s.selected_id
  end

  # --- search ---

  def test_jump_to_next_match_selects_the_next_match_after_current
    s = state
    a = session("a", title: "apple")
    b = session("b", title: "nothing")
    c = session("c", title: "apricot")
    visible = [a, b, c]
    s.selected_id = "a"
    s.search_text = "ap"
    assert s.jump_to_next_match(visible)
    assert_equal "c", s.selected_id
  end

  def test_jump_to_next_match_wraps_around
    s = state
    a = session("a", title: "apple")
    b = session("b", title: "nothing")
    visible = [a, b]
    s.selected_id = "a"
    s.search_text = "apple"
    assert s.jump_to_next_match(visible) # only match is "a" itself -> wraps to itself
    assert_equal "a", s.selected_id
  end

  def test_jump_to_next_match_returns_false_when_nothing_matches
    s = state
    s.search_text = "nonexistent"
    refute s.jump_to_next_match([session("a", title: "x")])
  end

  def test_jump_to_next_match_returns_false_for_empty_search
    s = state
    s.search_text = ""
    refute s.jump_to_next_match([session("a")])
  end
end
