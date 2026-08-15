# frozen_string_literal: true

require_relative "../test_helper"

class Commands__DailyTest < Minitest::Test
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

  def run_daily(argv, sessions)
    command = Aiwatch::Commands::Daily.new(
      argv, adapter: FakeAdapter.new(sessions), pricing_table: FakePricingTable.new(PRICE)
    )
    capture_io { @exit_code = command.run }
  end

  def test_renders_a_table_by_default
    session = build_session(input: 1000)
    out, = run_daily([], [session])

    assert_equal 0, @exit_code
    assert_includes out, "DATE"
    assert_includes out, "SESSIONS"
  end

  def test_json_flag_emits_parseable_rows
    session = build_session(input: 1000)
    out, = run_daily(["--json"], [session])

    parsed = JSON.parse(out)
    assert_equal 1, parsed.length
    assert_equal 1000, parsed.first["input_tokens"]
  end
end
