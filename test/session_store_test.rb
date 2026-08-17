# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

class SessionStoreTest < Minitest::Test
  def with_project_dir
    Dir.mktmpdir do |dir|
      proj = File.join(dir, "-home-x-proj")
      FileUtils.mkdir_p(proj)
      yield dir, proj
    end
  end

  def assistant_line(id, tokens, ts = "2026-08-17T09:00:00.000Z")
    {
      "type" => "assistant", "timestamp" => ts, "cwd" => "/home/x/proj",
      "message" => {"id" => id, "model" => "claude-sonnet-5", "usage" => {"input_tokens" => 1, "output_tokens" => tokens}}
    }.to_json
  end

  def store_for(dir, **opts)
    Aiwatch::SessionStore.new(adapter: Aiwatch::Adapters::ClaudeCode.new(dir: dir), **opts)
  end

  def test_discovers_a_session_and_reads_its_content
    with_project_dir do |dir, proj|
      File.write(File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"), assistant_line("m1", 100) + "\n")
      sessions = store_for(dir).refresh
      assert_equal 1, sessions.length
      assert_equal 100, sessions.first.total_output_tokens
    end
  end

  def test_second_refresh_reads_only_newly_appended_content
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(path, assistant_line("m1", 100) + "\n")
      store = store_for(dir)
      store.refresh

      File.open(path, "a") { |f| f.write(assistant_line("m2", 50) + "\n") }
      sessions = store.refresh
      assert_equal 150, sessions.first.total_output_tokens
    end
  end

  def test_dedupes_a_repeated_message_id_across_separate_reads
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(path, assistant_line("m1", 100) + "\n")
      store = store_for(dir)
      store.refresh

      File.open(path, "a") { |f| f.write(assistant_line("m1", 999) + "\n") }
      sessions = store.refresh
      assert_equal 100, sessions.first.total_output_tokens
    end
  end

  def test_a_new_session_file_appearing_later_is_discovered
    with_project_dir do |dir, proj|
      File.write(File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"), assistant_line("m1", 1) + "\n")
      store = store_for(dir)
      assert_equal 1, store.refresh.length

      File.write(File.join(proj, "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"), assistant_line("n1", 1) + "\n")
      assert_equal 2, store.refresh.length
    end
  end

  def test_a_deleted_session_file_is_pruned
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(path, assistant_line("m1", 1) + "\n")
      store = store_for(dir)
      assert_equal 1, store.refresh.length

      File.delete(path)
      assert_equal 0, store.refresh.length
    end
  end

  def test_cold_start_on_a_large_file_marks_totals_partial_and_backfill_completes_exactly
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.open(path, "w") { |f| 500.times { |i| f.write(assistant_line("m#{i}", 10) + "\n") } }

      store = store_for(dir, tail_bytes: 2_000, backfill_budget_bytes: 500)
      s = store.refresh.first
      assert s.totals_partial?
      assert_operator s.total_output_tokens, :<, 5_000

      300.times do
        break unless s.totals_partial?
        s = store.refresh.first
      end
      refute s.totals_partial?
      assert_equal 5_000, s.total_output_tokens
    end
  end

  def test_rotation_rebuilds_the_session_instead_of_carrying_stale_totals
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(path, assistant_line("m1", 100) + "\n" + assistant_line("m2", 50) + "\n")
      store = store_for(dir)
      assert_equal 150, store.refresh.first.total_output_tokens

      sleep 0.01
      File.delete(path)
      File.write(path, assistant_line("m1", 5) + "\n")
      assert_equal 5, store.refresh.first.total_output_tokens
    end
  end

  def test_ai_title_is_reflected_in_the_returned_session
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(path, {"type" => "ai-title", "aiTitle" => "Fix the bug"}.to_json + "\n" + assistant_line("m1", 1) + "\n")
      sessions = store_for(dir).refresh
      assert_equal "Fix the bug", sessions.first.title
    end
  end

  def test_feed_events_are_populated_from_content_bearing_lines
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      user_line = {"type" => "user", "timestamp" => "2026-08-17T09:00:00.000Z", "message" => {"content" => "please fix this"}}.to_json
      File.write(path, user_line + "\n")
      sessions = store_for(dir).refresh
      assert_equal 1, sessions.first.feed.length
      assert_equal :user, sessions.first.feed.first.kind
    end
  end

  def test_unchanged_files_are_not_reopened_on_a_later_refresh
    with_project_dir do |dir, proj|
      changed_path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      unchanged_path = File.join(proj, "bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(changed_path, assistant_line("m1", 1) + "\n")
      File.write(unchanged_path, assistant_line("n1", 1) + "\n")

      store = store_for(dir)
      store.refresh

      opened = []
      original_open = File.method(:open)
      File.define_singleton_method(:open) do |path, *args, &block|
        opened << path
        original_open.call(path, *args, &block)
      end

      begin
        File.open(changed_path, "a") { |f| f.write(assistant_line("m2", 1) + "\n") }
        sleep 0.01 # nudge mtime forward on filesystems with coarse resolution
        File.utime(Time.now, Time.now, changed_path)
        store.refresh
      ensure
        File.singleton_class.send(:remove_method, :open)
      end

      assert_includes opened, changed_path
      refute_includes opened, unchanged_path
    end
  end

  def test_malformed_lines_are_counted_as_skipped_without_raising
    with_project_dir do |dir, proj|
      path = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
      File.write(path, assistant_line("m1", 1) + "\n{not json\n" + assistant_line("m2", 1) + "\n")
      sessions = store_for(dir).refresh
      assert_equal 2, sessions.first.total_output_tokens
    end
  end
end
