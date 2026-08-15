# frozen_string_literal: true

module Aiwatch
  module Commands
    class Show < Base
      private

      def execute
        prefix = @positional.first
        unless prefix
          warn "aiwatch: show requires a session id (or a unique prefix of one)"
          return 1
        end

        matches = sessions.select { |s| s.id.start_with?(prefix) }

        if matches.empty?
          warn "aiwatch: no session found matching '#{prefix}'"
          return 1
        elsif matches.length > 1
          warn "aiwatch: '#{prefix}' matches more than one session:"
          matches.each { |s| warn "  #{s.id}" }
          return 1
        end

        session = matches.first
        warn_pricing_fallback!

        if json?
          puts Renderers::Json.new(cost_calculator).render_show(session)
        else
          puts Renderers::Table.new(cost_calculator).render_show(session)
        end
        0
      end
    end
  end
end
