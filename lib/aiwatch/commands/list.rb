# frozen_string_literal: true

module Aiwatch
  module Commands
    class List < Base
      DEFAULT_SINCE = "7d"
      SINCE_PATTERN = /\A(\d+)d\z/

      private

      def default_options
        super.merge(since: DEFAULT_SINCE, threshold_minutes: 5)
      end

      def add_options(o)
        o.on("--since DURATION", "Only sessions active within this window, e.g. 7d, 30d (default: #{DEFAULT_SINCE})") do |v|
          @options[:since] = v
        end
        o.on("--all", "Include sessions of any age") { @options[:since] = nil }
        o.on("--active-minutes N", Integer, "Minutes of inactivity before a session is no longer 'active' (default: 5)") do |v|
          @options[:threshold_minutes] = v
        end
      end

      def execute
        cutoff = parse_since(@options[:since])
        now = Time.now
        filtered = sessions.select { |s| cutoff.nil? || (s.last_seen_at && s.last_seen_at >= cutoff) }
        sorted = filtered.sort_by { |s| s.last_seen_at || Time.at(0) }.reverse

        warn_pricing_fallback!

        threshold = @options[:threshold_minutes]
        if json?
          puts Renderers::Json.new(cost_calculator).render_list(sorted, now: now, active_threshold_minutes: threshold)
        else
          puts Renderers::Table.new(cost_calculator).render_list(sorted, now: now, color: color?, active_threshold_minutes: threshold)
        end
        0
      end

      def parse_since(value)
        return nil if value.nil?

        match = SINCE_PATTERN.match(value)
        raise OptionParser::InvalidArgument, "--since must look like '7d' or '30d' (or use --all)" unless match

        Time.now - (match[1].to_i * 86_400)
      end
    end
  end
end
