# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tempfile"

class RenderersLiveTest < Minitest::Test
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

  # Returns a fresh single-session snapshot each call, with output_tokens
  # taken from `totals_sequence` in order — simulates a session's usage
  # growing tick over tick.
  class GrowingFakeAdapter
    def initialize(totals_sequence, id:, file_path:)
      @totals_sequence = totals_sequence
      @id = id
      @file_path = file_path
      @call_index = 0
    end

    def discover_sessions
      output = @totals_sequence[@call_index] || @totals_sequence.last
      @call_index += 1
      session = Aiwatch::Session.new(id: @id, file_path: @file_path)
      session.add_event(Aiwatch::UsageEvent.new(
        message_id: "m-#{@call_index}", model: "claude-sonnet-5", timestamp: Time.now, cwd: "/x",
        input_tokens: 0, output_tokens: output, cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
      ))
      [session]
    end
  end

  # A minimal IO-like object that reports as a TTY, so color-dependent
  # rendering (never exercised by plain StringIO, which is how a real
  # alignment bug went uncaught before) actually runs under test.
  class FakeTTY
    def initialize
      @io = StringIO.new
    end

    def tty?
      true
    end

    def print(*args)
      @io.print(*args)
    end

    def puts(*args)
      @io.puts(*args)
    end

    def flush
    end

    def string
      @io.string
    end
  end

  def calculator
    Aiwatch::CostCalculator.new(FakePricingTable.new(PRICE))
  end

  # Ticks n times, then requests a quit, returning everything written to `out`.
  def run_ticks(sessions, n)
    out = StringIO.new
    ticks = 0
    quit = ->(_timeout) {
      ticks += 1
      ticks >= n
    }

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

  # Regression test: setup_terminal puts the tty into raw mode, which
  # disables the terminal's own \n -> \r\n translation for the whole
  # device (stdin and stdout share one tty). A renderer that emits bare
  # "\n" then draws each line starting wherever the previous one's cursor
  # ended, cascading further right every frame — this is what the user
  # actually saw, independent of column width or Unicode width.
  def test_every_line_ends_with_crlf_so_raw_mode_does_not_cascade_lines
    Tempfile.create("aiwatch-live-crlf") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out, = run_ticks([session], 1)
      frame = out.split("\e[H\e[2J").last

      refute_includes frame.gsub("\r\n", ""), "\n", "found a bare \\n not paired with \\r in: #{frame.inspect}"
    end
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

  def test_tokens_header_shows_the_actual_history_window
    Tempfile.create("aiwatch-live-header") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out, = run_ticks([session], 1)

      # sparkline_width defaults to 20 (40 samples) at the default 2s
      # refresh => 80s of history.
      assert_includes out, "TOKENS/s (80s)"
    end
  end

  def test_custom_sparkline_width_and_refresh_change_the_window_label
    Tempfile.create("aiwatch-live-header2") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out = StringIO.new
      live = Aiwatch::Renderers::Live.new(
        adapter: FakeAdapter.new([session]), cost_calculator: calculator,
        out: out, in_stream: StringIO.new, quit_requested: ->(_) { true },
        sparkline_width: 4, refresh_seconds: 2
      )
      live.run

      assert_includes out.string, "TOKENS/s (16s)"
    end
  end

  def test_sparkline_reflects_token_growth_across_ticks
    Tempfile.create("aiwatch-live-growth") do |file|
      File.utime(Time.now, Time.now, file.path)
      adapter = GrowingFakeAdapter.new([0, 50, 120], id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file.path)

      ticks = 0
      quit = ->(_timeout) {
        ticks += 1
        ticks >= 3
      }
      out = StringIO.new
      live = Aiwatch::Renderers::Live.new(
        adapter: adapter, cost_calculator: calculator, out: out, in_stream: StringIO.new,
        quit_requested: quit, sparkline_width: 4
      )
      live.run

      last_frame = out.string.split("\e[H\e[2J").last
      data_line = last_frame.lines.find { |l| l.include?("aaaaaaaa") }

      refute_nil data_line
      codepoints = data_line.codepoints.select { |cp| cp.between?(0x2800, 0x28FF) }
      assert(codepoints.any? { |cp| cp > 0x2800 }, "expected at least one non-blank sparkline cell after growth")
    end
  end

  def test_long_project_and_model_list_are_truncated_so_the_row_does_not_wrap
    Tempfile.create("aiwatch-live-wide") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(
        file_path: file.path,
        project: "/home/someone/work/a/very/deeply/nested/project/directory/path/name",
        model: "claude-sonnet-5"
      )
      session.add_event(Aiwatch::UsageEvent.new(
        message_id: "m2", model: "claude-opus-5", timestamp: Time.now, cwd: session.project,
        input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
      ))

      out, = run_ticks([session], 1)
      data_line = out.lines.find { |l| l.include?(session.short_id) }

      refute_nil data_line
      assert(data_line.length < 120, "expected row to stay well under terminal width, was #{data_line.length} chars")
      assert_includes data_line, "…"
    end
  end

  def test_each_session_gets_a_stable_distinct_color_in_first_seen_order
    Tempfile.create("aiwatch-live-a") do |file_a|
      Tempfile.create("aiwatch-live-b") do |file_b|
        [file_a, file_b].each { |f| File.utime(Time.now, Time.now, f.path) }

        a = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_a.path)
        b = build_session(id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_b.path)

        out = FakeTTY.new
        ticks = 0
        quit = ->(_timeout) {
          ticks += 1
          ticks >= 2
        }
        live = Aiwatch::Renderers::Live.new(
          adapter: FakeAdapter.new([a, b]), cost_calculator: calculator,
          out: out, in_stream: StringIO.new, quit_requested: quit
        )
        live.run

        frames = out.string.split("\e[H\e[2J").reject(&:empty?)
        assert_equal 2, frames.length

        colors_per_frame = frames.map do |frame|
          line_a = frame.lines.find { |l| l.include?("aaaaaaaa") }
          line_b = frame.lines.find { |l| l.include?("bbbbbbbb") }
          color_of = ->(line) { line[/\e\[1;(\d+)m/, 1] }
          [color_of.call(line_a), color_of.call(line_b)]
        end

        # Both sessions got a color, they differ from each other, and each
        # session keeps the same color across ticks.
        first_a, first_b = colors_per_frame.first
        refute_nil first_a
        refute_nil first_b
        refute_equal first_a, first_b
        assert(colors_per_frame.all? { |a_color, b_color| [a_color, b_color] == [first_a, first_b] })
      end
    end
  end
end
