# frozen_string_literal: true

require "test_helper"
require_relative "../support/frame"
require "stringio"
require "tmpdir"
require "fileutils"
require "json"

# Phase 5/6 interaction coverage: everything beyond basic nav/kill/quit,
# already covered by test/renderers/live_test.rb. Same real-fixture-file
# harness, kept intentionally light here — one file per concern.
class LiveAppInteractionsTest < Minitest::Test
  PRICE = {
    "claude-sonnet-5" => {"input_cost_per_token" => 1e-6, "output_cost_per_token" => 0, "max_input_tokens" => 200_000}
  }.freeze

  def with_project_dir
    Dir.mktmpdir do |dir|
      proj = File.join(dir, "-home-x-proj")
      FileUtils.mkdir_p(proj)
      yield dir, proj
    end
  end

  def assistant_line(id, tokens, ts)
    {"type" => "assistant", "timestamp" => ts, "cwd" => "/home/x/proj",
     "message" => {"id" => id, "model" => "claude-sonnet-5", "usage" => {"input_tokens" => 1, "output_tokens" => tokens}}}.to_json
  end

  def write_session(proj, id:, title:, ts: nil)
    ts ||= Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    path = File.join(proj, "#{id}.jsonl")
    File.write(path, [{"type" => "ai-title", "aiTitle" => title}.to_json, assistant_line("m-#{id}", 10, ts)].join("\n") + "\n")
    path
  end

  def live_process_match(path, pid: 555)
    slug = File.basename(File.dirname(path))
    -> { [{pid: pid, cwd: "/home/x/proj", slug: slug, cmdline: %w[claude]}] }
  end

  def run_app(dir, keys:, out: StringIO.new, size: [160, 40], **opts)
    store = Aiwatch::SessionStore.new(adapter: Aiwatch::Adapters::ClaudeCode.new(dir: dir))
    pt = FakePricingTable.new(PRICE)
    screen = Aiwatch::Tui::Screen.new(out: out, in_stream: StringIO.new, size_reader: -> { size }, diff: false, altscreen: false)
    theme = Aiwatch::Tui::Theme.new(depth: :none)
    Aiwatch::Renderers::Live.new(
      store: store, cost_calculator: Aiwatch::CostCalculator.new(pt), pricing_table: pt,
      screen: screen, theme: theme, active_threshold_minutes: 5, refresh_seconds: 0,
      read_key: Aiwatch::Live::Input::Scripted.new(keys),
      process_finder_all: opts[:process_finder_all] || -> { [] },
      process_finder: opts[:process_finder] || ->(*) {},
      git_branch: opts[:git_branch] || ->(*) {},
      proc_stats: Aiwatch::ProcStats.new(proc_root: "/nonexistent-proc-root"),
      killer: opts[:killer] || ->(*) {}
    ).run
    out.string
  end

  def last_frame(output)
    Frame.frames(output).last
  end

  def test_force_kill_sends_sigkill_not_sigterm
    with_project_dir do |dir, proj|
      path = write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "S")
      killed_with = nil
      run_app(dir, keys: ["X", "y"], process_finder_all: live_process_match(path),
        process_finder: ->(*) { 111 }, killer: ->(pid, sig) { killed_with = [pid, sig] })
      assert_equal [111, "KILL"], killed_with
    end
  end

  def test_kill_all_requires_typed_yes_not_a_single_keypress
    with_project_dir do |dir, proj|
      path = write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "S")
      killed = false
      # A single "y" keypress must NOT trigger a kill-all.
      run_app(dir, keys: ["K", "y"], process_finder_all: live_process_match(path),
        process_finder: ->(*) { 111 }, killer: ->(*) { killed = true })
      refute killed
    end
  end

  def test_kill_all_with_typed_yes_kills_every_visible_active_session
    with_project_dir do |dir, proj1|
      # Two DIFFERENT project directories — sharing one would make both
      # sessions match the same slug ambiguously (2 candidates), which
      # this project's ProcessFinder policy correctly refuses to resolve
      # (nil rather than a guess), leaving both marked dead.
      proj2 = File.join(dir, "-home-x-proj2")
      FileUtils.mkdir_p(proj2)
      path1 = write_session(proj1, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "One")
      path2 = write_session(proj2, id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Two")
      slug1 = File.basename(File.dirname(path1))
      slug2 = File.basename(File.dirname(path2))
      procs = -> { [{pid: 1, cwd: "/home/x/proj1", slug: slug1, cmdline: %w[claude]}, {pid: 2, cwd: "/home/x/proj2", slug: slug2, cmdline: %w[claude]}] }
      killed_pids = []
      run_app(dir, keys: ["K", "y", "e", "s", :enter], process_finder_all: procs,
        process_finder: ->(path) { path.include?("aaaaaaaa") ? 1 : 2 },
        killer: ->(pid, sig) { killed_pids << pid if sig == "TERM" })
      assert_equal [1, 2], killed_pids.sort
    end
  end

  def test_pin_moves_a_session_to_the_top_regardless_of_sort
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Older", ts: (Time.now.utc - 100).strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      write_session(proj, id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Newer", ts: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      # default selection is the most-recent ("Newer"); pin it isn't useful here, so pin "Older" via down+p
      frame = last_frame(run_app(dir, keys: [:down, "p"]))
      lines = frame.each_row.to_a.map(&:plain)
      older_idx = lines.index { |l| l.include?("Older") }
      newer_idx = lines.index { |l| l.include?("Newer") }
      assert_operator older_idx, :<, newer_idx
    end
  end

  def test_purge_removes_dead_sessions_from_the_table
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Ghost")
      frame = Frame.new(run_app(dir, keys: ["A"], process_finder_all: -> { [] }))
      refute frame.row_containing("Ghost")
    end
  end

  def test_filter_narrows_the_table_to_matching_sessions
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Fix login bug")
      write_session(proj, id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Unrelated task")
      output = run_app(dir, keys: ["/", "l", "o", "g", "i", "n", :enter])
      frame = last_frame(output)
      assert frame.row_containing("Fix login bug")
      refute frame.row_containing("Unrelated task")
    end
  end

  def test_search_jumps_selection_to_the_matching_session
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "First", ts: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      write_session(proj, id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Findme", ts: (Time.now.utc - 1).strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      frame = last_frame(run_app(dir, keys: ["F", "F", "i", "n", "d", :enter]))
      assert_includes frame.row_containing("Findme").plain, ">"
    end
  end

  def test_cycle_sort_changes_order_from_last_activity_to_name
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Zebra", ts: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      write_session(proj, id: "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee", title: "Apple", ts: (Time.now.utc - 1).strftime("%Y-%m-%dT%H:%M:%S.000Z"))
      # sort order cycles last_activity -> cost -> started -> name
      frame = last_frame(run_app(dir, keys: ["s", "s", "s"]))
      lines = frame.each_row.to_a.map(&:plain)
      apple_idx = lines.index { |l| l.include?("Apple") }
      zebra_idx = lines.index { |l| l.include?("Zebra") }
      assert_operator apple_idx, :<, zebra_idx
    end
  end

  def test_views_switch_and_esc_returns_to_dash
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "S")
      # frame 0 is the initial render before any key; "W" produces frame 1, :esc produces frame 2.
      frames = Frame.frames(run_app(dir, keys: ["W", :esc]))
      assert frames[1].row_containing("Timeline")
      assert frames[2].row_containing("AIWATCH")
    end
  end

  def test_help_overlay_shows_and_esc_closes_it
    with_project_dir do |dir, _proj|
      frames = Frame.frames(run_app(dir, keys: ["?", :esc]))
      assert frames[1].row_containing("Help")
      assert frames[2].row_containing("AIWATCH")
    end
  end

  def test_open_writes_the_resume_command_to_the_footer
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", title: "S")
      frame = last_frame(run_app(dir, keys: ["o"]))
      assert frame.row_containing("claude --resume aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    end
  end
end
