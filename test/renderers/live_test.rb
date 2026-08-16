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

  # Runs `live` feeding it exactly `events` in order (each a read_event
  # return value — :timeout, :up, :down, :kill, :confirm, :cancel), then
  # :quit once the queue is exhausted. One render happens before the loop
  # even starts, so events.length + 1 renders happen for an all-:timeout
  # queue (each :timeout also triggers a real data refresh).
  def run_with(adapter:, events:, out: StringIO.new, **opts)
    queue = events.dup
    read_event = ->(_timeout) { queue.empty? ? :quit : queue.shift }

    live = Aiwatch::Renderers::Live.new(
      adapter: adapter, cost_calculator: calculator, out: out, in_stream: StringIO.new,
      read_event: read_event, **opts
    )
    live.run
    out.respond_to?(:string) ? out.string : out
  end

  def run_events(sessions, events, **opts)
    run_with(adapter: FakeAdapter.new(sessions), events: events, **opts)
  end

  def test_renders_only_active_sessions
    Tempfile.create("aiwatch-live-active") do |active_file|
      Tempfile.create("aiwatch-live-stale") do |stale_file|
        File.utime(Time.now, Time.now, active_file.path)
        File.utime(Time.now - 3600, Time.now - 3600, stale_file.path)

        active = build_session(id: "11111111-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: active_file.path)
        stale = build_session(id: "22222222-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: stale_file.path)

        out = run_events([active, stale], [])

        assert_includes out, "11111111"
        refute_includes out, "22222222"
        assert_includes out, "1 active session(s)"
      end
    end
  end

  def test_shows_placeholder_when_nothing_is_active
    out = run_events([], [])

    assert_includes out, "0 active session(s)"
    assert_includes out, "(no active sessions)"
  end

  def test_refreshes_once_per_timeout_until_quit
    out = run_events([], [:timeout, :timeout])

    assert_equal 3, out.scan("\e[H\e[2J").length
  end

  def test_restores_the_terminal_on_quit
    out = run_events([], [])

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
      out: out, in_stream: StringIO.new, read_event: ->(_) { :quit }
    )

    assert_raises(RuntimeError) { live.run }
    assert_includes out.string, "\e[?25h"
  end

  def test_tokens_header_shows_the_actual_history_window
    Tempfile.create("aiwatch-live-header") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out = run_events([session], [])

      # sparkline_width defaults to 20 (40 samples) at the default 2s
      # refresh => 80s of history.
      assert_includes out, "TOKENS/s (80s)"
    end
  end

  def test_custom_sparkline_width_and_refresh_change_the_window_label
    Tempfile.create("aiwatch-live-header2") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out = run_events([session], [], sparkline_width: 4, refresh_seconds: 2)

      assert_includes out, "TOKENS/s (16s)"
    end
  end

  def test_sparkline_reflects_token_growth_across_ticks
    Tempfile.create("aiwatch-live-growth") do |file|
      File.utime(Time.now, Time.now, file.path)
      adapter = GrowingFakeAdapter.new([0, 50, 120], id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file.path)

      out = run_with(adapter: adapter, events: [:timeout, :timeout], sparkline_width: 4)

      last_frame = out.split("\e[H\e[2J").last
      # The detail panel's "Session:  aaaaaaaa-..." line also matches; the
      # table row (with the sparkline) is the last matching line, not the
      # first.
      data_line = last_frame.lines.reverse.find { |l| l.include?("aaaaaaaa") }

      refute_nil data_line
      codepoints = data_line.codepoints.select { |cp| cp.between?(0x2800, 0x28FF) }
      assert(codepoints.any? { |cp| cp > 0x2800 }, "expected at least one non-blank sparkline cell after growth")
    end
  end

  def test_every_line_ends_with_crlf_so_raw_mode_does_not_cascade_lines
    Tempfile.create("aiwatch-live-crlf") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out = run_events([session], [])
      frame = out.split("\e[H\e[2J").last

      refute_includes frame.gsub("\r\n", ""), "\n", "found a bare \\n not paired with \\r in: #{frame.inspect}"
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

      out = run_events([session], [])
      # The detail panel's "Session:  <full-uuid>" line also starts with
      # the short id; the table row is the last matching line.
      data_line = out.lines.reverse.find { |l| l.include?(session.short_id) }

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

        out = run_events([a, b], [:timeout], out: FakeTTY.new)

        frames = out.split("\e[H\e[2J").reject(&:empty?)
        assert_equal 2, frames.length

        colors_per_frame = frames.map do |frame|
          line_a = frame.lines.reverse.find { |l| l.include?("aaaaaaaa") }
          line_b = frame.lines.reverse.find { |l| l.include?("bbbbbbbb") }
          color_of = ->(line) { line[/\e\[1;(\d+)m/, 1] }
          [color_of.call(line_a), color_of.call(line_b)]
        end

        first_a, first_b = colors_per_frame.first
        refute_nil first_a
        refute_nil first_b
        refute_equal first_a, first_b
        assert(colors_per_frame.all? { |a_color, b_color| [a_color, b_color] == [first_a, first_b] })
      end
    end
  end

  # --- Interactive navigation and detail panel ---

  def test_first_session_is_selected_by_default_and_shown_in_the_detail_panel
    Tempfile.create("aiwatch-live-a") do |file_a|
      Tempfile.create("aiwatch-live-b") do |file_b|
        [file_a, file_b].each { |f| File.utime(Time.now, Time.now, f.path) }
        a = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_a.path, timestamp: Time.now)
        b = build_session(id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_b.path, timestamp: Time.now - 10)

        out = run_events([a, b], [])

        assert_includes out, "Session:  aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        data_lines = out.lines.select { |l| l.include?("aaaaaaaa") || l.include?("bbbbbbbb") }
        assert(data_lines.any? { |l| l.start_with?(">") && l.include?("aaaaaaaa") })
      end
    end
  end

  def test_down_arrow_moves_selection_to_the_next_session_and_updates_the_panel
    Tempfile.create("aiwatch-live-a") do |file_a|
      Tempfile.create("aiwatch-live-b") do |file_b|
        [file_a, file_b].each { |f| File.utime(Time.now, Time.now, f.path) }
        a = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_a.path, timestamp: Time.now)
        b = build_session(id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_b.path, timestamp: Time.now - 10)

        out = run_events([a, b], [:down])
        last_frame = out.split("\e[H\e[2J").last

        assert_includes last_frame, "Session:  bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee"
      end
    end
  end

  def test_selection_does_not_move_past_the_last_session
    Tempfile.create("aiwatch-live-a") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)

      out = run_events([session], [:down, :down])
      last_frame = out.split("\e[H\e[2J").last

      assert_includes last_frame, "Session:  #{session.id}"
    end
  end

  def test_up_arrow_moves_selection_back_up
    Tempfile.create("aiwatch-live-a") do |file_a|
      Tempfile.create("aiwatch-live-b") do |file_b|
        [file_a, file_b].each { |f| File.utime(Time.now, Time.now, f.path) }
        a = build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_a.path, timestamp: Time.now)
        b = build_session(id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: file_b.path, timestamp: Time.now - 10)

        out = run_events([a, b], [:down, :up])
        last_frame = out.split("\e[H\e[2J").last

        assert_includes last_frame, "Session:  aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      end
    end
  end

  # --- Kill flow ---

  def test_x_shows_a_confirmation_prompt_without_killing_yet
    Tempfile.create("aiwatch-live-kill") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)
      killed = false

      out = run_events([session], [:kill], process_finder: ->(_path) { 999 }, killer: ->(_pid, _sig) { killed = true })
      last_frame = out.split("\e[H\e[2J").last

      assert_includes last_frame, "Kill session #{session.short_id}? y = confirm, n/Esc = cancel"
      refute killed
    end
  end

  def test_confirming_a_kill_sends_sigterm_to_the_process_found_for_that_session
    Tempfile.create("aiwatch-live-kill") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)
      calls = []
      finder = ->(path) {
        calls << [:find, path]
        4242
      }
      killer = ->(pid, signal) { calls << [:kill, pid, signal] }

      out = run_events([session], [:kill, :confirm], process_finder: finder, killer: killer)

      assert_equal [:find, session.project], calls[0]
      assert_equal [:kill, 4242, "TERM"], calls[1]
      assert_includes out, "Sent SIGTERM to process 4242"
    end
  end

  def test_cancelling_a_kill_does_not_call_the_killer
    Tempfile.create("aiwatch-live-kill") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)
      killed = false

      out = run_events(
        [session], [:kill, :cancel],
        process_finder: ->(_path) { 999 }, killer: ->(_pid, _sig) { killed = true }
      )

      refute killed
      last_frame = out.split("\e[H\e[2J").last
      refute_includes last_frame, "Kill session"
    end
  end

  def test_kill_reports_when_no_process_is_found_for_the_session
    Tempfile.create("aiwatch-live-kill") do |file|
      File.utime(Time.now, Time.now, file.path)
      session = build_session(file_path: file.path)
      killed = false

      out = run_events(
        [session], [:kill, :confirm],
        process_finder: ->(_path) {}, killer: ->(_pid, _sig) { killed = true }
      )

      refute killed
      assert_includes out, "Could not find a running process for session #{session.short_id}"
    end
  end
end
