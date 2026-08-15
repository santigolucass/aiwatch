# frozen_string_literal: true

require "optparse"

module Aiwatch
  module Commands
    class Base
      def initialize(argv, adapter: nil, pricing_table: nil)
        @options = default_options
        @adapter_override = adapter
        @pricing_table_override = pricing_table
        @parser = build_parser
        @parser.parse!(argv)
        @positional = argv
      end

      def run
        return help! if @options[:help]

        execute
      end

      private

      def command_name
        self.class.name.split("::").last.downcase
      end

      def default_options
        {help: false, dir: nil, json: false}
      end

      def build_parser
        OptionParser.new do |o|
          o.banner = "Usage: aiwatch #{command_name} [options]"
          o.on("--dir DIR", "Override the Claude Code logs directory") { |v| @options[:dir] = v }
          o.on("--json", "Emit JSON instead of a table") { @options[:json] = true }
          add_options(o)
          o.on("-h", "--help", "Show this help") { @options[:help] = true }
        end
      end

      def add_options(_parser)
      end

      def help!
        puts @parser
        0
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      def adapter
        @adapter_override ||= @options[:dir] ? Adapters::ClaudeCode.new(dir: @options[:dir]) : Adapters::ClaudeCode.new
      end

      def pricing_table
        @pricing_table_override ||= PricingTable.new
      end

      def cost_calculator
        @cost_calculator ||= CostCalculator.new(pricing_table)
      end

      def sessions
        adapter.discover_sessions
      end

      def warn_pricing_fallback!
        pricing_table.prices # force the lazy load so #warnings is populated
        pricing_table.warnings.each { |w| warn "aiwatch: #{w}" }
      end

      def json?
        @options[:json]
      end

      def color?
        $stdout.tty?
      end
    end
  end
end
