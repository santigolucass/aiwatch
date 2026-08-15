# frozen_string_literal: true

require_relative "aiwatch/version"
require_relative "aiwatch/usage_event"
require_relative "aiwatch/model_usage"
require_relative "aiwatch/session"
require_relative "aiwatch/adapters/base"
require_relative "aiwatch/adapters/claude_code"
require_relative "aiwatch/pricing_table"
require_relative "aiwatch/cost_calculator"
require_relative "aiwatch/format"
require_relative "aiwatch/daily_aggregator"
require_relative "aiwatch/renderers/text_table"
require_relative "aiwatch/renderers/braille_sparkline"
require_relative "aiwatch/renderers/table"
require_relative "aiwatch/renderers/json"
require_relative "aiwatch/renderers/live"
require_relative "aiwatch/commands/base"
require_relative "aiwatch/commands/list"
require_relative "aiwatch/commands/daily"
require_relative "aiwatch/commands/show"
require_relative "aiwatch/commands/live"
require_relative "aiwatch/cli"

module Aiwatch
end
