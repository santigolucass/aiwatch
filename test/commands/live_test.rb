# frozen_string_literal: true

require_relative "../test_helper"

class CommandsLiveTest < Minitest::Test
  PRICE = {}.freeze

  class FakeAdapter
    def discover_sessions
      []
    end
  end

  class FakeLive
    class << self
      attr_accessor :last_args
    end

    def initialize(**args)
      self.class.last_args = args
    end

    def run
      # no-op: never actually blocks on a terminal in tests
    end
  end

  def setup
    FakeLive.last_args = nil
  end

  def test_passes_default_options_to_the_renderer
    command = Aiwatch::Commands::Live.new(
      [], adapter: FakeAdapter.new, pricing_table: FakePricingTable.new(PRICE), live_class: FakeLive
    )
    exit_code = command.run

    assert_equal 0, exit_code
    assert_equal 5, FakeLive.last_args[:active_threshold_minutes]
    assert_equal Aiwatch::Renderers::Live::REFRESH_SECONDS, FakeLive.last_args[:refresh_seconds]
  end

  def test_passes_custom_active_minutes_and_refresh
    command = Aiwatch::Commands::Live.new(
      ["--active-minutes", "10", "--refresh", "0.5"],
      adapter: FakeAdapter.new, pricing_table: FakePricingTable.new(PRICE), live_class: FakeLive
    )
    command.run

    assert_equal 10, FakeLive.last_args[:active_threshold_minutes]
    assert_in_delta 0.5, FakeLive.last_args[:refresh_seconds], 1e-9
  end
end
