# frozen_string_literal: true

module Aiwatch
  # Turns token usage into an estimated dollar cost using a PricingTable.
  #
  # cost = input*input_rate + output*output_rate + cache_read*cache_read_rate
  #        + cache_creation_1h*above_1hr_rate + cache_creation_5m*standard_rate
  #
  # A model absent from the pricing table prices as nil, never a silent 0 —
  # see docs/decisions.md.
  class CostCalculator
    Total = Struct.new(:amount, :unknown_models) do
      def fully_known?
        unknown_models.empty?
      end
    end

    def initialize(pricing_table)
      @pricing_table = pricing_table
    end

    # Hash[model] => Float cost, or nil for a model missing from the pricing table.
    def costs_for(session)
      session.model_usages.transform_values { |usage| cost_for(usage) }
    end

    def cost_for(model_usage)
      price = @pricing_table.price_for(model_usage.model)
      return nil unless price

      (model_usage.input_tokens * price.fetch("input_cost_per_token", 0)) +
        (model_usage.output_tokens * price.fetch("output_cost_per_token", 0)) +
        (model_usage.cache_read_tokens * price.fetch("cache_read_input_token_cost", 0)) +
        (model_usage.cache_creation_1h_tokens * cache_creation_1h_rate(price)) +
        (model_usage.cache_creation_5m_tokens * (price["cache_creation_input_token_cost"] || 0))
    end

    def total_for(session)
      per_model = costs_for(session)
      known = per_model.values.compact
      unknown_models = per_model.select { |_, cost| cost.nil? }.keys

      Total.new(amount: known.sum, unknown_models: unknown_models)
    end

    private

    # 1h-TTL cache creation bills at cache_creation_input_token_cost_above_1hr.
    # Fall back to the standard (5m) rate if a price entry lacks it, rather
    # than treating 1h tokens as free.
    def cache_creation_1h_rate(price)
      price["cache_creation_input_token_cost_above_1hr"] || price["cache_creation_input_token_cost"] || 0
    end
  end
end
