# frozen_string_literal: true

module Aiwatch
  module Commands
    class Daily < Base
      private

      def execute
        warn_pricing_fallback!
        rows = DailyAggregator.new(cost_calculator).aggregate(sessions)

        if json?
          puts Renderers::Json.new(cost_calculator).render_daily(rows)
        else
          puts Renderers::Table.new(cost_calculator).render_daily(rows)
        end
        0
      end
    end
  end
end
