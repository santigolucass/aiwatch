# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "fileutils"

class AdaptersClaudeCodeTest < Minitest::Test
  include FixturePath

  def adapter
    Aiwatch::Adapters::ClaudeCode.new(dir: fixture_path("claude_code"))
  end

  def demo_session
    adapter.discover_sessions.find { |s| s.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  end

  def test_discovers_the_fixture_session
    sessions = adapter.discover_sessions

    assert_equal 1, sessions.length
  end

  def test_dedupes_repeated_message_ids
    sonnet = demo_session.model_usages.fetch("claude-sonnet-5")

    # msg_0001 appears twice in the fixture with identical usage; it must
    # only be counted once. Eligible sonnet events: msg_0001, msg_0003, msg_0004.
    assert_equal 3, sonnet.event_count
  end

  def test_aggregates_tokens_correctly_across_deduped_events
    sonnet = demo_session.model_usages.fetch("claude-sonnet-5")

    assert_equal 100 + 5 + 5, sonnet.input_tokens
    assert_equal 50 + 5 + 5, sonnet.output_tokens
    assert_equal 200, sonnet.cache_read_tokens
    # msg_0001: 1000 at 1h tier. msg_0003 (no breakdown) and msg_0004
    # (inconsistent breakdown) both fall back fully to the 5m tier.
    assert_equal 1000, sonnet.cache_creation_1h_tokens
    assert_equal 500 + 300, sonnet.cache_creation_5m_tokens
  end

  def test_tracks_a_second_model_in_the_same_session
    opus = demo_session.model_usages.fetch("claude-opus-5")

    assert_equal 1, opus.event_count
    assert_equal 10, opus.input_tokens
    assert_equal 5, opus.output_tokens
  end

  def test_skips_synthetic_model_without_counting_it_as_a_parse_error
    session = demo_session

    refute session.models.include?("<synthetic>")
  end

  def test_counts_the_malformed_json_line_as_skipped
    assert_equal 1, demo_session.skipped_lines
  end

  def test_ignores_assistant_lines_missing_timestamp_or_usage
    sonnet = demo_session.model_usages.fetch("claude-sonnet-5")

    # msg_0005 (no timestamp) and msg_0006 (no usage) must not appear.
    assert_equal 3, sonnet.event_count
  end

  def test_project_comes_from_cwd_not_the_directory_slug
    assert_equal "/home/testuser/code/demo-project", demo_session.project
  end

  def test_title_is_the_last_ai_title_line_seen_not_the_first
    # The fixture has two ai-title lines for this session; the later one
    # ("Wire up billing...") must win, since Claude Code regenerates the
    # title as the session progresses.
    assert_equal "Wire up billing for demo project", demo_session.title
  end

  def test_reports_provider_name
    assert_equal "claude-code", adapter.name
  end

  def test_missing_directory_returns_no_sessions_without_raising
    adapter = Aiwatch::Adapters::ClaudeCode.new(dir: fixture_path("does-not-exist"))

    assert_equal [], adapter.discover_sessions
  end

  def test_subagent_files_finds_files_nested_under_a_parent_sessions_subagents_dir
    Dir.mktmpdir do |dir|
      proj = File.join(dir, "-home-x-proj")
      sub_dir = File.join(proj, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "subagents")
      FileUtils.mkdir_p(sub_dir)
      path = File.join(sub_dir, "agent-abc123.jsonl")
      File.write(path, "")

      found = Aiwatch::Adapters::ClaudeCode.new(dir: dir).subagent_files
      assert_equal [path], found
    end
  end

  def test_subagent_files_is_empty_when_no_session_has_subagents
    assert_equal [], adapter.subagent_files
  end
end
