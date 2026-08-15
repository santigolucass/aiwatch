# frozen_string_literal: true

require_relative "../test_helper"

class Commands__ListTest < Minitest::Test
  include SessionFactory

  PRICE = {
    "claude-sonnet-5" => {
      "input_cost_per_token" => 1e-6, "output_cost_per_token" => 2e-6,
      "cache_read_input_token_cost" => 0, "cache_creation_input_token_cost" => 0,
      "cache_creation_input_token_cost_above_1hr" => 0
    }
  }.freeze

  class FakeAdapter
    def initialize(sessions)
      @sessions = sessions
    end

    def discover_sessions
      @sessions
    end
  end

  def run_list(argv, sessions)
    command = Aiwatch::Commands::List.new(
      argv, adapter: FakeAdapter.new(sessions), pricing_table: FakePricingTable.new(PRICE)
    )
    out, err = capture_io { @exit_code = command.run }
    [out, err]
  end

  def test_lists_sessions_as_a_table_by_default
    session = build_session(timestamp: Time.now)
    out, = run_list([], [session])

    assert_equal 0, @exit_code
    assert_includes out, "SESSION"
    assert_includes out, session.short_id
  end

  def test_json_flag_emits_parseable_json
    session = build_session
    out, = run_list(["--json"], [session])

    parsed = JSON.parse(out)
    assert_equal 1, parsed.length
    assert_equal session.id, parsed.first["session_id"]
  end

  def test_since_filters_out_old_sessions
    recent = build_session(id: "1" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", timestamp: Time.now - 3600)
    old = build_session(id: "2" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", timestamp: Time.now - (10 * 86_400))

    out, = run_list(["--since", "7d"], [recent, old])

    assert_includes out, "11111111"
    refute_includes out, "22222222"
  end

  def test_all_flag_includes_old_sessions
    old = build_session(id: "3" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", timestamp: Time.now - (365 * 86_400))

    out, = run_list(["--all"], [old])

    assert_includes out, "33333333"
  end

  def test_invalid_since_format_raises
    assert_raises(OptionParser::InvalidArgument) do
      Aiwatch::Commands::List.new(
        ["--since", "banana"], adapter: FakeAdapter.new([]), pricing_table: FakePricingTable.new(PRICE)
      ).run
    end
  end

  def test_sorts_most_recent_activity_first
    older = build_session(id: "4" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", timestamp: Time.now - 3600)
    newer = build_session(id: "5" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", timestamp: Time.now - 60)

    out, = run_list(["--all"], [older, newer])
    lines = out.lines.reject { |l| l.strip.empty? }

    assert lines.index { |l| l.include?("55555555") } < lines.index { |l| l.include?("44444444") }
  end
end
