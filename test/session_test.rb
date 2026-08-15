# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class SessionTest < Minitest::Test
  def build_event(**overrides)
    defaults = {
      message_id: "msg_1", model: "claude-sonnet-5", timestamp: Time.now, cwd: "/home/x/project",
      input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    }
    Aiwatch::UsageEvent.new(**defaults.merge(overrides))
  end

  def test_aggregates_events_per_model_and_tracks_time_range
    session = Aiwatch::Session.new(id: "sess-1", file_path: "/dev/null")
    t1 = Time.iso8601("2026-08-01T10:00:00Z")
    t2 = Time.iso8601("2026-08-01T10:05:00Z")

    session.add_event(build_event(model: "claude-sonnet-5", timestamp: t2, cwd: "/home/x/project"))
    session.add_event(build_event(model: "claude-opus-5", timestamp: t1, cwd: "/home/x/project"))

    assert_equal %w[claude-sonnet-5 claude-opus-5], session.models
    assert_equal t1, session.first_seen_at
    assert_equal t2, session.last_seen_at
    refute session.empty?
  end

  def test_project_is_the_most_frequent_cwd
    session = Aiwatch::Session.new(id: "sess-1", file_path: "/dev/null")
    session.add_event(build_event(cwd: "/home/x/a"))
    session.add_event(build_event(cwd: "/home/x/b"))
    session.add_event(build_event(cwd: "/home/x/b"))

    assert_equal "/home/x/b", session.project
  end

  def test_empty_session_has_no_project_and_is_empty
    session = Aiwatch::Session.new(id: "sess-1", file_path: "/dev/null")

    assert session.empty?
    assert_nil session.project
  end

  def test_active_depends_on_file_mtime
    Tempfile.create("aiwatch-session") do |file|
      session = Aiwatch::Session.new(id: "sess-1", file_path: file.path)

      File.utime(Time.now, Time.now, file.path)
      assert session.active?(threshold_minutes: 5)

      old = Time.now - (60 * 60)
      File.utime(old, old, file.path)
      refute session.active?(threshold_minutes: 5)
    end
  end

  def test_short_id
    session = Aiwatch::Session.new(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: "/dev/null")

    assert_equal "aaaaaaaa", session.short_id
  end
end
