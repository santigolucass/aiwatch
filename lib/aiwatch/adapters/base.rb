# frozen_string_literal: true

module Aiwatch
  module Adapters
    # Contract every provider adapter implements.
    class Base
      # Returns an Array of Aiwatch::Session.
      def discover_sessions
        raise NotImplementedError, "#{self.class} must implement #discover_sessions"
      end

      # Human-readable name shown in output, e.g. "claude-code".
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end
    end
  end
end
