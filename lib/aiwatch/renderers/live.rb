# frozen_string_literal: true

module Aiwatch
  module Renderers
    # Thin facade preserving `aiwatch live`'s original entry point and
    # class name — the actual dashboard is Live::App; everything here
    # does is forward construction to it.
    class Live
      REFRESH_SECONDS = Aiwatch::Live::App::REFRESH_SECONDS

      def initialize(**opts)
        @app = Aiwatch::Live::App.new(**opts)
      end

      def run
        @app.run
      end
    end
  end
end
