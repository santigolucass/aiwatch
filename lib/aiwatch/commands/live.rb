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
        super.merge(threshold_minutes: 5, refresh_seconds: Renderers::Live::REFRESH_SECONDS, ascii: false, altscreen: true, proc: true)
      end

      def add_options(o)
        o.on("--active-minutes N", Integer, "Minutes of inactivity before a session drops out of live (default: 5)") do |v|
          @options[:threshold_minutes] = v
        end
        o.on("--refresh SECONDS", Float, "Refresh interval in seconds (default: #{Renderers::Live::REFRESH_SECONDS})") do |v|
          @options[:refresh_seconds] = v
        end
        o.on("--ascii", "Use plain ASCII glyphs instead of Unicode box-drawing/Braille") { @options[:ascii] = true }
        o.on("--no-altscreen", "Don't switch to the terminal's alternate screen buffer") { @options[:altscreen] = false }
        o.on("--snapshot", "Render a single frame to stdout and exit") { @options[:snapshot] = true }
        o.on("--no-proc", "Skip /proc scanning (PID/CPU/MEM/branch/dead-detection); required on non-Linux") { @options[:proc] = false }
      end

      def execute
        warn_pricing_fallback!
        live_opts = {
          store: SessionStore.new(adapter: adapter),
          cost_calculator: cost_calculator,
          pricing_table: pricing_table,
          screen: Tui::Screen.new(altscreen: @options[:altscreen] && !@options[:snapshot]),
          theme: Tui::Theme.new(depth: Tui::Theme.detect, ascii: @options[:ascii]),
          active_threshold_minutes: @options[:threshold_minutes],
          refresh_seconds: @options[:refresh_seconds],
          snapshot: @options[:snapshot]
        }
        unless @options[:proc]
          live_opts[:process_finder_all] = -> { [] }
          live_opts[:proc_stats] = ProcStats.new(proc_root: "/nonexistent")
        end
        @live_class.new(**live_opts).run
        0
      end
    end
  end
end
