# frozen_string_literal: true

require "test_helper"

class FeedBuilderTest < Minitest::Test
  def build
    feed = Aiwatch::RingBuffer.new(50)
    [Aiwatch::FeedBuilder.new(feed: feed), feed]
  end

  def assistant(content_type, content_extra = {}, message_extra = {})
    {
      "type" => "assistant", "timestamp" => "2026-08-17T09:00:00.000Z",
      "message" => {
        "id" => "m1", "model" => "claude-sonnet-5",
        "usage" => {"input_tokens" => 2, "cache_read_input_tokens" => 100, "cache_creation_input_tokens" => 5},
        "content" => [{"type" => content_type}.merge(content_extra)]
      }.merge(message_extra)
    }
  end

  def test_text_block_pushes_an_assistant_feed_event
    builder, feed = build
    builder.ingest(assistant("text", "text" => "hello world"), {})
    assert_equal 1, feed.length
    assert_equal :assistant, feed.first.kind
    assert_equal "hello world", feed.first.text
  end

  def test_tool_use_blocks_are_clustered_until_flushed_by_text
    builder, feed = build
    builder.ingest(assistant("tool_use", "name" => "Bash"), {})
    builder.ingest({"type" => "assistant", "timestamp" => "t", "message" => {"id" => "m2", "model" => "x", "usage" => {},
                                                                             "content" => [{"type" => "tool_use", "name" => "Read"}]}}, {})
    assert_equal 0, feed.length

    builder.ingest(assistant("text", "text" => "done"), {})
    assert_equal 2, feed.length
    assert_equal :tool, feed.to_a[0].kind
    assert_equal "Executed 2 tools: [Bash -> Read]", feed.to_a[0].text
  end

  def test_single_tool_singular_wording
    builder, feed = build
    builder.ingest(assistant("tool_use", "name" => "Bash"), {})
    builder.flush!
    assert_equal "Executed 1 tool: [Bash]", feed.first.text
  end

  def test_mcp_tool_names_are_shortened_to_the_tool_part
    builder, feed = build
    builder.ingest(assistant("tool_use", "name" => "mcp__atlassian__getJiraIssue"), {})
    builder.flush!
    assert_equal "Executed 1 tool: [getJiraIssue]", feed.first.text
  end

  def test_skips_narration_for_already_seen_message_ids
    builder, feed = build
    seen = {"m1" => true}
    builder.ingest(assistant("text", "text" => "hello"), seen)
    assert_equal 0, feed.length
  end

  def test_thinking_blocks_are_not_narrated
    builder, feed = build
    builder.ingest(assistant("thinking", "thinking" => "pondering"), {})
    assert_equal 0, feed.length
  end

  def test_updates_context_occupancy_side_channel
    builder, = build
    builder.ingest(assistant("text", "text" => "hi"), {})
    assert_equal 107, builder.ctx_tokens # 2 + 100 + 5
    assert_equal "claude-sonnet-5", builder.ctx_model
  end

  def test_updates_stop_reason_and_effort
    builder, = build
    line = assistant("text", {"text" => "hi"}, {"stop_reason" => "end_turn"})
    line["effort"] = "high"
    builder.ingest(line, {})
    assert_equal "end_turn", builder.stop_reason
    assert_equal "high", builder.effort
  end

  def test_user_string_content_pushes_a_user_feed_event
    builder, feed = build
    builder.ingest({"type" => "user", "timestamp" => "t", "message" => {"content" => "please fix this"}}, {})
    assert_equal :user, feed.first.kind
    assert_equal "please fix this", feed.first.text
  end

  def test_user_tool_result_pushes_a_result_feed_event
    builder, feed = build
    builder.ingest({"type" => "user", "timestamp" => "t",
      "message" => {"content" => [{"type" => "tool_result", "is_error" => false}]}}, {})
    assert_equal :result, feed.first.kind
    assert_equal "ok", feed.first.text
  end

  def test_user_tool_result_error_is_reported
    builder, feed = build
    builder.ingest({"type" => "user", "timestamp" => "t",
      "message" => {"content" => [{"type" => "tool_result", "is_error" => true}]}}, {})
    assert_equal "error", feed.first.text
  end

  def test_turn_duration_updates_side_channel
    builder, = build
    builder.ingest({"type" => "system", "subtype" => "turn_duration", "durationMs" => 52918}, {})
    assert_equal 52918, builder.turn_ms
  end

  def test_compact_boundary_increments_count_and_pushes_a_feed_event
    builder, feed = build
    builder.ingest({"type" => "system", "subtype" => "compact_boundary",
      "compactMetadata" => {"preTokens" => 379643, "postTokens" => 16664}}, {})
    assert_equal 1, builder.compactions
    assert_equal :compact, feed.first.kind
    assert_includes feed.first.text, "379643"
    assert_includes feed.first.text, "16664"
  end

  def test_pr_link_pushes_a_feed_event
    builder, feed = build
    builder.ingest({"type" => "pr-link", "timestamp" => "t", "prNumber" => 929, "prUrl" => "https://x"}, {})
    assert_equal :pr, feed.first.kind
    assert_includes feed.first.text, "929"
  end

  def test_permission_mode_updates_side_channel_without_a_feed_event
    builder, feed = build
    builder.ingest({"type" => "permission-mode", "permissionMode" => "plan"}, {})
    assert_equal "plan", builder.permission_mode
    assert_equal 0, feed.length
  end

  def test_unknown_line_types_are_ignored_without_raising
    builder, feed = build
    builder.ingest({"type" => "something-unheard-of", "foo" => "bar"}, {})
    assert_equal 0, feed.length
  end

  def test_malformed_shapes_do_not_raise
    builder, = build
    builder.ingest({"type" => "assistant", "message" => "not a hash"}, {})
    builder.ingest({"type" => "user", "message" => nil}, {})
    builder.ingest({"type" => "system", "subtype" => "compact_boundary", "compactMetadata" => "nope"}, {})
  end

  def test_long_text_is_snipped
    builder, feed = build
    long_text = "x" * 500
    builder.ingest(assistant("text", "text" => long_text), {})
    assert_operator feed.first.text.length, :<=, Aiwatch::FeedBuilder::SNIPPET_LENGTH + 1
  end
end
