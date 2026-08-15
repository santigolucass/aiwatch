# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tempfile"

class Renderers__LiveTest < Minitest::Test
  include SessionFactory

  PRICE = {
    "claude-sonnet-5" => {"input_cost_per_token" => 1e-6, "output_cost_per_token" => 0}
  }.freeze

  class FakeAdapter
    def initialize(sessions)
      @sessions = sessions
    end

    def discover_sessions
      @sessions
    end
  end

  def calculator
    Aiwatch::CostCalculator.new(FakePricingTable.new(PRICE))
  end

  # Ticks n times, then requests a quit, returning everything written to `out`.
  def run_ticks(sessions, n)
    out = StringIO.new
    ticks = 0
    quit = ->(_timeout) { ticks += 1; ticks >= n }

    live = Aiwatch::Renderers::Live.new(
      adapter: FakeAdapter.new(sessions), cost_calculator: calculator,
      out: out, in_stream: StringIO.new, quit_requested: quit
    )
    live.run
    [out.string, ticks]
  end

  def test_renders_only_active_sessions
    Tempfile.create("aiwatch-live-active") do |active_file|
      Tempfile.create("aiwatch-live-stale") do |stale_file|
        File.utime(Time.now, Time.now, active_file.path)
        File.utime(Time.now - 3600, Time.now - 3600, stale_file.path)

        active = build_session(id: "11111111-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: active_file.path)
        stale = build_session(id: "22222222-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: stale_file.path)

        out, = run_ticks([active, stale], 1)

        assert_includes out, "11111111"
        refute_includes out, "22222222"
        assert_includes out, "1 active session(s)"
      end
    end
  end

  def test_shows_placeholder_when_nothing_is_active
    out, = run_ticks([], 1)

    assert_includes out, "0 active session(s)"
    assert_includes out, "no active sessions"
  end

  def test_refreshes_once_per_tick_until_quit
    out, ticks = run_ticks([], 3)

    assert_equal 3, ticks
    assert_equal 3, out.scan("press q to quit").length
  end

  def test_restores_the_terminal_on_quit
    out, = run_ticks([], 1)

    assert_includes out, "\e[?25h"
  end

  def test_restores_the_terminal_even_if_rendering_raises
    out = StringIO.new
    adapter = Object.new
    def adapter.discover_sessions
      raise "boom"
    end

    live = Aiwatch::Renderers::Live.new(
      adapter: adapter, cost_calculator: calculator,
      out: out, in_stream: StringIO.new, quit_requested: ->(_) { true }
    )

    assert_raises(RuntimeError) { live.run }
    assert_includes out.string, "\e[?25h"
  end
end
