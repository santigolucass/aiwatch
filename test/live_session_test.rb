# frozen_string_literal: true

require "test_helper"

class LiveSessionTest < Minitest::Test
  def test_delegates_read_methods_to_the_wrapped_session
    session = Aiwatch::Session.new(id: "abc123", file_path: "/x/abc123.jsonl")
    live = Aiwatch::LiveSession.new(session: session)
    assert_equal "abc123", live.id
    assert_equal "/x/abc123.jsonl", live.file_path
  end

  def test_ingest_forwards_to_the_feed_builder_and_feed_is_readable
    session = Aiwatch::Session.new(id: "s1", file_path: File::NULL)
    live = Aiwatch::LiveSession.new(session: session)
    live.ingest({"type" => "user", "timestamp" => "2026-08-17T09:00:00.000Z", "message" => {"content" => "hi"}}, {})
    assert_equal 1, live.feed.length
    assert_equal :user, live.feed.first.kind
  end

  def test_process_and_dashboard_fields_default_to_nil_or_false
    session = Aiwatch::Session.new(id: "s1", file_path: File::NULL)
    live = Aiwatch::LiveSession.new(session: session)
    assert_nil live.pid
    assert_nil live.cpu_percent
    refute live.dead?
    refute live.pinned?
    refute live.totals_partial?
  end

  def test_process_and_dashboard_fields_are_settable
    session = Aiwatch::Session.new(id: "s1", file_path: File::NULL)
    live = Aiwatch::LiveSession.new(session: session)
    live.pid = 1234
    live.cpu_percent = 12.5
    live.branch = "main"
    live.dead = true
    live.pinned = true
    live.totals_partial = true
    assert_equal 1234, live.pid
    assert_equal 12.5, live.cpu_percent
    assert_equal "main", live.branch
    assert live.dead?
    assert live.pinned?
    assert live.totals_partial?
  end

  def test_side_channel_readers_delegate_to_the_feed_builder
    session = Aiwatch::Session.new(id: "s1", file_path: File::NULL)
    live = Aiwatch::LiveSession.new(session: session)
    live.ingest({"type" => "system", "subtype" => "turn_duration", "durationMs" => 100}, {})
    assert_equal 100, live.turn_ms
  end
end
