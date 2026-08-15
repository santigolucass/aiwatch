# frozen_string_literal: true

require_relative "test_helper"

class CostCalculatorTest < Minitest::Test
  class FakePricingTable
    def initialize(prices)
      @prices = prices
    end

    def price_for(model)
      @prices[model]
    end
  end

  SONNET_PRICE = {
    "input_cost_per_token" => 2e-6,
    "output_cost_per_token" => 1e-5,
    "cache_creation_input_token_cost" => 2.5e-6,
    "cache_creation_input_token_cost_above_1hr" => 4e-6,
    "cache_read_input_token_cost" => 2e-7
  }.freeze

  def build_usage(model: "claude-sonnet-5", **overrides)
    defaults = {
      message_id: "m1", model: model, timestamp: Time.now, cwd: "/x",
      input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    }
    usage = Aiwatch::ModelUsage.new(model: model)
    usage.add(Aiwatch::UsageEvent.new(**defaults.merge(overrides)))
    usage
  end

  def calculator(prices)
    Aiwatch::CostCalculator.new(FakePricingTable.new(prices))
  end

  def test_computes_cost_from_input_output_and_cache_read
    usage = build_usage(input_tokens: 1_000_000, output_tokens: 1_000_000, cache_read_input_tokens: 1_000_000)
    calc = calculator("claude-sonnet-5" => SONNET_PRICE)

    expected = (1_000_000 * 2e-6) + (1_000_000 * 1e-5) + (1_000_000 * 2e-7)
    assert_in_delta expected, calc.cost_for(usage), 1e-9
  end

  # Regression test for the finding that pricing all cache creation at the
  # 5m rate understates real cost: the 1h and 5m tiers must be billed
  # separately at their own rates, not pooled into one flat rate.
  def test_bills_1h_and_5m_cache_creation_at_different_rates
    usage = build_usage(cache_creation_1h_tokens: 1_000_000, cache_creation_5m_tokens: 1_000_000)
    calc = calculator("claude-sonnet-5" => SONNET_PRICE)

    expected = (1_000_000 * 4e-6) + (1_000_000 * 2.5e-6)
    naive_flat_rate = 2_000_000 * 2.5e-6

    actual = calc.cost_for(usage)
    assert_in_delta expected, actual, 1e-9
    refute_in_delta naive_flat_rate, actual, 1e-9
  end

  def test_falls_back_to_standard_rate_when_above_1hr_rate_is_absent
    usage = build_usage(cache_creation_1h_tokens: 1_000_000)
    price = SONNET_PRICE.reject { |k, _| k == "cache_creation_input_token_cost_above_1hr" }
    calc = calculator("claude-sonnet-5" => price)

    assert_in_delta 1_000_000 * 2.5e-6, calc.cost_for(usage), 1e-9
  end

  def test_unknown_model_prices_as_nil_not_zero
    usage = build_usage(model: "totally-unknown-model", input_tokens: 100)
    calc = calculator({})

    assert_nil calc.cost_for(usage)
  end

  def test_total_for_session_sums_known_models_and_lists_unknown_ones
    session = Aiwatch::Session.new(id: "s1", file_path: "/dev/null")
    session.add_event(Aiwatch::UsageEvent.new(
      message_id: "m1", model: "claude-sonnet-5", timestamp: Time.now, cwd: "/x",
      input_tokens: 1_000_000, output_tokens: 0, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    ))
    session.add_event(Aiwatch::UsageEvent.new(
      message_id: "m2", model: "mystery-model", timestamp: Time.now, cwd: "/x",
      input_tokens: 500, output_tokens: 0, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    ))

    calc = calculator("claude-sonnet-5" => SONNET_PRICE)
    total = calc.total_for(session)

    assert_in_delta 1_000_000 * 2e-6, total.amount, 1e-9
    assert_equal ["mystery-model"], total.unknown_models
    refute total.fully_known?
  end
end
