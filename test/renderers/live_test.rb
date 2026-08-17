# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/frame"
require "stringio"
require "tmpdir"
require "fileutils"
require "json"

# End-to-end tests for the full-screen dashboard (Aiwatch::Live::App, via
# the Renderers::Live facade). Unlike the old single-view `live`, the
# dashboard reads real session files on disk (SessionStore tails them
# incrementally) rather than an in-memory adapter double, so every test
# here builds real fixture JSONL files under a tempdir.
class RenderersLiveTest < Minitest::Test
  PRICE = {
    "claude-sonnet-5" => {"input_cost_per_token" => 1e-6, "output_cost_per_token" => 0, "max_input_tokens" => 200_000}
  }.freeze

  class CountingStore
    attr_reader :call_count

    def initialize(inner)
      @inner = inner
      @call_count = 0
    end

    def refresh(priority_id: nil)
      @call_count += 1
      @inner.refresh(priority_id: priority_id)
    end
  end

  def with_project_dir
    Dir.mktmpdir do |dir|
      proj = File.join(dir, "-home-x-proj")
      FileUtils.mkdir_p(proj)
      yield dir, proj
    end
  end

  def assistant_line(id, tokens, ts)
    {
      "type" => "assistant", "timestamp" => ts, "cwd" => "/home/x/proj",
      "message" => {"id" => id, "model" => "claude-sonnet-5", "usage" => {"input_tokens" => 1, "output_tokens" => tokens}}
    }.to_json
  end

  def write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Fix the bug", tokens: 100, ts: nil)
    ts ||= Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    path = File.join(proj, "#{id}.jsonl")
    lines = [{"type" => "ai-title", "aiTitle" => title}.to_json, assistant_line("m-#{id}", tokens, ts)]
    File.write(path, lines.join("\n") + "\n")
    path
  end

  # A process_finder_all seam matching exactly one live process to the
  # given session file — the session reads as ACTIVE (not dead) and thus
  # killable, the same as a real running `claude` process would.
  def live_process_match(path, pid: 555)
    slug = File.basename(File.dirname(path))
    -> { [{pid: pid, cwd: "/home/x/proj", slug: slug, cmdline: %w[claude]}] }
  end

  def build_app(dir, keys:, out: StringIO.new, size: [100, 30], now: Time.now,
    store: nil, process_finder_all: -> { [] }, process_finder: ->(*) {},
    git_branch: ->(*) {}, killer: ->(*) {})
    store ||= Aiwatch::SessionStore.new(adapter: Aiwatch::Adapters::ClaudeCode.new(dir: dir))
    cost_calculator = Aiwatch::CostCalculator.new(FakePricingTable.new(PRICE))
    screen = Aiwatch::Tui::Screen.new(out: out, in_stream: StringIO.new, size_reader: -> { size }, diff: false, altscreen: false)
    theme = Aiwatch::Tui::Theme.new(depth: :none)
    pricing_table = FakePricingTable.new(PRICE)

    Aiwatch::Renderers::Live.new(
      store: store, cost_calculator: cost_calculator, pricing_table: pricing_table,
      screen: screen, theme: theme, active_threshold_minutes: 5, refresh_seconds: 0,
      clock: -> { now }, read_key: Aiwatch::Live::Input::Scripted.new(keys),
      process_finder_all: process_finder_all, git_branch: git_branch,
      proc_stats: Aiwatch::ProcStats.new(proc_root: "/nonexistent-proc-root"),
      killer: killer, process_finder: process_finder
    )
  end

  def run_app(dir, keys:, out: StringIO.new, **opts)
    build_app(dir, keys: keys, out: out, **opts).run
    out.string
  end

  def test_shows_a_placeholder_style_table_when_nothing_is_active
    with_project_dir do |dir, _proj|
      frame = Frame.new(run_app(dir, keys: []))
      assert frame.row_containing("0 total")
    end
  end

  def test_renders_a_discovered_session_in_the_table
    with_project_dir do |dir, proj|
      write_session(proj, title: "Fix the bug")
      frame = Frame.new(run_app(dir, keys: []))
      row = frame.row_containing("Fix the bug")
      refute_nil row
      assert_includes row.plain, "DEAD" # no live process matched -> dead, not gone
    end
  end

  def test_no_rendered_row_exceeds_the_terminal_width
    with_project_dir do |dir, proj|
      write_session(proj, title: "A very very very extremely long session title that should never overflow the terminal width")
      [60, 80, 100, 140, 200].each do |width|
        frame = Frame.new(run_app(dir, keys: [], size: [width, 30]))
        frame.each_row { |row| assert_operator row.plain.length, :<=, width, "row #{row.number} overflowed at width #{width}" }
      end
    end
  end

  def test_down_then_up_arrow_moves_selection
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "First", ts: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      write_session(proj, id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Second", ts: (Time.now.utc - 1).strftime("%Y-%m-%dT%H:%M:%S.000Z"))

      frames = Frame.frames(run_app(dir, keys: [:down, :up], size: [140, 30]))
      assert_includes frames[0].row_containing("First").plain, ">"
      assert_includes frames[1].row_containing("Second").plain, ">"
      assert_includes frames[2].row_containing("First").plain, ">"
    end
  end

  def test_x_shows_a_confirmation_prompt_without_killing_yet
    with_project_dir do |dir, proj|
      path = write_session(proj)
      killed = false
      output = run_app(dir, keys: ["x"], process_finder_all: live_process_match(path), killer: ->(*) { killed = true })
      frame = Frame.frames(output).last
      assert frame.row_containing("y = confirm")
      refute killed
    end
  end

  def test_y_confirms_the_kill_and_calls_the_killer
    with_project_dir do |dir, proj|
      path = write_session(proj)
      killed_with = nil
      run_app(dir, keys: ["x", "y"], process_finder_all: live_process_match(path),
        process_finder: ->(*) { 4242 }, killer: ->(pid, sig) { killed_with = [pid, sig] })
      assert_equal [4242, "TERM"], killed_with
    end
  end

  def test_n_cancels_the_kill_without_calling_the_killer
    with_project_dir do |dir, proj|
      path = write_session(proj)
      killed = false
      output = run_app(dir, keys: ["x", "n"], process_finder_all: live_process_match(path), killer: ->(*) { killed = true })
      refute killed
      frame = Frame.frames(output).last
      refute frame.row_containing("y = confirm")
    end
  end

  def test_kill_reports_when_no_process_is_found
    with_project_dir do |dir, proj|
      path = write_session(proj)
      output = run_app(dir, keys: ["x", "y"], process_finder_all: live_process_match(path), process_finder: ->(*) {})
      frame = Frame.frames(output).last
      assert frame.row_containing("Could not find a running process")
    end
  end

  def test_r_forces_a_refresh_via_the_same_path_as_a_timeout
    with_project_dir do |dir, proj|
      write_session(proj)
      inner = Aiwatch::SessionStore.new(adapter: Aiwatch::Adapters::ClaudeCode.new(dir: dir))
      counting = CountingStore.new(inner)
      run_app(dir, keys: ["1", "r"], store: counting) # "1" is an unmapped no-op key
      # one call on startup, one more for the explicit "r" refresh
      assert_equal 2, counting.call_count
    end
  end

  def test_restores_the_terminal_on_quit
    with_project_dir do |dir, _proj|
      out = StringIO.new
      run_app(dir, keys: [], out: out)
      assert_includes out.string, "\e[?25h"
    end
  end

  def test_restores_the_terminal_even_if_a_key_handler_raises
    with_project_dir do |dir, proj|
      path = write_session(proj)
      out = StringIO.new
      app = build_app(dir, keys: ["x", "y"], out: out, process_finder_all: live_process_match(path), process_finder: ->(*) { raise "boom" })
      assert_raises(RuntimeError) { app.run }
      assert_includes out.string, "\e[?25h"
    end
  end

  def test_dead_sessions_remain_visible_and_are_labeled_dead
    with_project_dir do |dir, proj|
      write_session(proj, title: "Orphaned")
      frame = Frame.new(run_app(dir, keys: [], size: [140, 30], process_finder_all: -> { [] }))
      row = frame.row_containing("Orphaned")
      assert_includes row.plain, "DEAD"
    end
  end

  def test_a_live_process_match_marks_the_session_active_with_a_pid
    with_project_dir do |dir, proj|
      path = write_session(proj, title: "Live one")
      slug = File.basename(File.dirname(path))
      procs = [{pid: 999, cwd: "/home/x/proj", slug: slug, cmdline: %w[claude]}]
      frame = Frame.new(run_app(dir, keys: [], process_finder_all: -> { procs }))
      row = frame.row_containing("Live one")
      assert_includes row.plain, "ACTIVE"
      assert_includes row.plain, "999"
    end
  end

  def test_footer_lists_the_key_reference
    with_project_dir do |dir, _proj|
      frame = Frame.new(run_app(dir, keys: [], size: [200, 30]))
      footer = frame[frame.rows.keys.max]
      assert_includes footer.plain, "Kill"
      assert_includes footer.plain, "Refresh"
    end
  end
end
