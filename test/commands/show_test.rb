# frozen_string_literal: true

require_relative "../test_helper"

class Commands__ShowTest < Minitest::Test
  include SessionFactory

  PRICE = {
    "claude-sonnet-5" => {"input_cost_per_token" => 1e-6, "output_cost_per_token" => 0}
  }.freeze

  class FakeAdapter
    def initialize(sessions)
      @sessions = sessions
    end

    def discover_sessions
      @sessions
    end
  end

  def run_show(argv, sessions)
    command = Aiwatch::Commands::Show.new(
      argv, adapter: FakeAdapter.new(sessions), pricing_table: FakePricingTable.new(PRICE)
    )
    capture_io { @exit_code = command.run }
  end

  def test_shows_detail_for_an_exact_id
    session = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    out, = run_show([session.id], [session])

    assert_equal 0, @exit_code
    assert_includes out, session.id
    assert_includes out, "claude-sonnet-5"
  end

  def test_resolves_a_unique_prefix_like_git
    session = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    out, = run_show(["aaaaaaaa"], [session])

    assert_equal 0, @exit_code
    assert_includes out, session.id
  end

  def test_ambiguous_prefix_lists_candidates_and_fails
    a = build_session(id: "aaaaaaaa-1111-cccc-dddd-eeeeeeeeeeee")
    b = build_session(id: "aaaaaaaa-2222-cccc-dddd-eeeeeeeeeeee")
    _, err = run_show(["aaaaaaaa"], [a, b])

    assert_equal 1, @exit_code
    assert_includes err, a.id
    assert_includes err, b.id
  end

  def test_unknown_id_fails
    _, err = run_show(["deadbeef"], [])

    assert_equal 1, @exit_code
    assert_includes err, "no session found"
  end

  def test_missing_id_argument_fails
    _, err = run_show([], [])

    assert_equal 1, @exit_code
    assert_includes err, "requires a session id"
  end

  def test_json_flag_emits_model_breakdown
    session = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    out, = run_show(["aaaaaaaa", "--json"], [session])

    parsed = JSON.parse(out)
    assert_equal session.id, parsed["session_id"]
    assert_equal 1, parsed["models"].length
  end
end
