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

  def write_session(proj, id:, tokens: 1)
    File.write(File.join(proj, "#{id}.jsonl"), assistant_line("m-#{id}", tokens) + "\n")
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

  def write_subagent(proj, parent_id:, agent_id:, description: nil, agent_type: nil, parent_agent_id: nil, tokens: 5)
    sub_dir = File.join(proj, parent_id, "subagents")
    FileUtils.mkdir_p(sub_dir)
    File.write(File.join(sub_dir, "agent-#{agent_id}.jsonl"), assistant_line("m-#{agent_id}", tokens) + "\n")
    meta = {}
    meta["description"] = description if description
    meta["agentType"] = agent_type if agent_type
    meta["parentAgentId"] = parent_agent_id if parent_agent_id
    File.write(File.join(sub_dir, "agent-#{agent_id}.meta.json"), meta.to_json)
  end

  def test_discovers_a_subagent_nested_under_its_parent_session
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", tokens: 1)
      write_subagent(proj, parent_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", agent_id: "abc123", description: "Do the thing", agent_type: "general-purpose")

      sessions = store_for(dir).refresh
      sub = sessions.find(&:subagent?)
      refute_nil sub
      assert_equal "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", sub.parent_id
      assert_equal "abc123", sub.agent_id
      assert_equal "Do the thing", sub.title
      assert_equal "general-purpose", sub.agent_type
      assert_equal 5, sub.total_output_tokens
    end
  end

  def test_subagent_with_no_description_has_a_nil_title
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", tokens: 1)
      write_subagent(proj, parent_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", agent_id: "abc123")

      sub = store_for(dir).refresh.find(&:subagent?)
      assert_nil sub.title
    end
  end

  def test_a_subagent_spawned_by_another_subagent_has_that_subagent_as_its_parent
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", tokens: 1)
      write_subagent(proj, parent_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", agent_id: "outer", description: "Outer")
      write_subagent(proj, parent_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", agent_id: "inner", description: "Inner", parent_agent_id: "outer")

      sessions = store_for(dir).refresh
      inner = sessions.find { |s| s.agent_id == "inner" }
      assert_equal "agent-outer", inner.parent_id
    end
  end

  def test_missing_meta_json_does_not_raise_and_leaves_title_nil
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", tokens: 1)
      sub_dir = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "subagents")
      FileUtils.mkdir_p(sub_dir)
      File.write(File.join(sub_dir, "agent-abc123.jsonl"), assistant_line("m1", 1) + "\n")

      sub = store_for(dir).refresh.find(&:subagent?)
      refute_nil sub
      assert_nil sub.title
    end
  end

  def test_malformed_meta_json_does_not_raise
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", tokens: 1)
      sub_dir = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "subagents")
      FileUtils.mkdir_p(sub_dir)
      File.write(File.join(sub_dir, "agent-abc123.jsonl"), assistant_line("m1", 1) + "\n")
      File.write(File.join(sub_dir, "agent-abc123.meta.json"), "{not json")

      sub = store_for(dir).refresh.find(&:subagent?)
      refute_nil sub
      assert_nil sub.title
    end
  end

  def test_top_level_sessions_are_never_marked_as_subagents
    with_project_dir do |dir, proj|
      write_session(proj, id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", tokens: 1)
      sessions = store_for(dir).refresh
      refute sessions.first.subagent?
    end
  end
end
