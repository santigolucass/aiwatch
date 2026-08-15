# frozen_string_literal: true

require_relative "../test_helper"

class Renderers__JsonTest < Minitest::Test
  include SessionFactory

  PRICE = {
    "claude-sonnet-5" => {
      "input_cost_per_token" => 1e-6, "output_cost_per_token" => 2e-6,
      "cache_read_input_token_cost" => 0, "cache_creation_input_token_cost" => 0,
      "cache_creation_input_token_cost_above_1hr" => 0
    }
  }.freeze

  def calculator
    Aiwatch::CostCalculator.new(FakePricingTable.new(PRICE))
  end

  def test_render_list_emits_a_stable_documented_shape
    session = build_session(input: 1000, output: 500)
    parsed = JSON.parse(Aiwatch::Renderers::Json.new(calculator).render_list([session]))

    assert_equal 1, parsed.length
    row = parsed.first
    assert_equal session.id, row["session_id"]
    assert_equal "/home/x/project", row["project"]
    assert_equal ["claude-sonnet-5"], row["models"]
    assert_equal 1000, row["input_tokens"]
    assert_equal 500, row["output_tokens"]
    assert_in_delta 0.0020, row["cost_usd"], 1e-9
    assert_equal true, row["fully_known"]
    assert row.key?("last_activity")
    assert row.key?("active")
  end

  def test_render_list_reports_unknown_models_as_not_fully_known
    session = build_session(model: "mystery-model")
    row = JSON.parse(Aiwatch::Renderers::Json.new(calculator).render_list([session])).first

    assert_equal false, row["fully_known"]
  end

  def test_render_show_includes_per_model_breakdown
    session = build_session(model: "claude-sonnet-5", input: 100, output: 50)
    parsed = JSON.parse(Aiwatch::Renderers::Json.new(calculator).render_show(session))

    assert_equal 1, parsed["models"].length
    assert_equal "claude-sonnet-5", parsed["models"].first["model"]
    assert_equal [], parsed["unknown_models"]
  end

  def test_render_daily_emits_expected_fields
    day = {date: "2026-08-10", session_count: 2, input_tokens: 100, output_tokens: 50,
           cache_read_tokens: 0, cache_creation_tokens: 0, cost: 0.5, fully_known: true}
    row = JSON.parse(Aiwatch::Renderers::Json.new(calculator).render_daily([day])).first

    assert_equal "2026-08-10", row["date"]
    assert_equal 2, row["session_count"]
    assert_in_delta 0.5, row["cost_usd"], 1e-9
  end
end
