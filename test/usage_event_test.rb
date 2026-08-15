# frozen_string_literal: true

require_relative "test_helper"

class UsageEventTest < Minitest::Test
  def assistant_line(overrides = {})
    {
      "type" => "assistant",
      "timestamp" => "2026-08-01T10:00:00.000Z",
      "cwd" => "/home/testuser/code/demo-project",
      "message" => {
        "id" => "msg_0001",
        "model" => "claude-sonnet-5",
        "usage" => {
          "input_tokens" => 100,
          "output_tokens" => 50,
          "cache_creation_input_tokens" => 1000,
          "cache_read_input_tokens" => 200,
          "cache_creation" => {
            "ephemeral_1h_input_tokens" => 1000,
            "ephemeral_5m_input_tokens" => 0
          }
        }
      }
    }.merge(overrides)
  end

  def test_parses_a_well_formed_assistant_line
    event = Aiwatch::UsageEvent.from_line(assistant_line)

    refute_nil event
    assert_equal "msg_0001", event.message_id
    assert_equal "claude-sonnet-5", event.model
    assert_equal 100, event.input_tokens
    assert_equal 50, event.output_tokens
    assert_equal 1000, event.cache_creation_1h_tokens
    assert_equal 0, event.cache_creation_5m_tokens
    assert_equal 200, event.cache_read_input_tokens
    assert_equal Time.iso8601("2026-08-01T10:00:00.000Z"), event.timestamp
  end

  def test_skips_non_assistant_lines
    assert_nil Aiwatch::UsageEvent.from_line(assistant_line("type" => "user"))
  end

  def test_skips_lines_without_usage
    line = assistant_line
    line["message"].delete("usage")

    assert_nil Aiwatch::UsageEvent.from_line(line)
  end

  def test_skips_synthetic_model
    line = assistant_line
    line["message"]["model"] = "<synthetic>"

    assert_nil Aiwatch::UsageEvent.from_line(line)
  end

  def test_skips_lines_missing_timestamp
    line = assistant_line
    line.delete("timestamp")

    assert_nil Aiwatch::UsageEvent.from_line(line)
  end

  def test_falls_back_to_5m_tier_when_breakdown_is_missing
    line = assistant_line
    line["message"]["usage"].delete("cache_creation")
    line["message"]["usage"]["cache_creation_input_tokens"] = 500

    event = Aiwatch::UsageEvent.from_line(line)

    assert_equal 0, event.cache_creation_1h_tokens
    assert_equal 500, event.cache_creation_5m_tokens
  end

  def test_falls_back_to_5m_tier_when_breakdown_does_not_reconcile
    line = assistant_line
    line["message"]["usage"]["cache_creation_input_tokens"] = 300
    line["message"]["usage"]["cache_creation"] = {
      "ephemeral_1h_input_tokens" => 100,
      "ephemeral_5m_input_tokens" => 100
    }

    event = Aiwatch::UsageEvent.from_line(line)

    assert_equal 0, event.cache_creation_1h_tokens
    assert_equal 300, event.cache_creation_5m_tokens
  end
end
