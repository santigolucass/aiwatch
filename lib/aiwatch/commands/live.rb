# frozen_string_literal: true

module Aiwatch
  module Commands
    class Live < Base
      def initialize(argv, live_class: Renderers::Live, **opts)
        super(argv, **opts)
        @live_class = live_class
      end

      private

      def default_options
        super.merge(threshold_minutes: 5, refresh_seconds: Renderers::Live::REFRESH_SECONDS)
      end

      def add_options(o)
        o.on("--active-minutes N", Integer, "Minutes of inactivity before a session drops out of live (default: 5)") do |v|
          @options[:threshold_minutes] = v
        end
        o.on("--refresh SECONDS", Float, "Refresh interval in seconds (default: #{Renderers::Live::REFRESH_SECONDS})") do |v|
          @options[:refresh_seconds] = v
        end
      end

      def execute
        warn_pricing_fallback!
        @live_class.new(
          adapter: adapter,
          cost_calculator: cost_calculator,
          active_threshold_minutes: @options[:threshold_minutes],
          refresh_seconds: @options[:refresh_seconds]
        ).run
        0
      end
    end
  end
end
