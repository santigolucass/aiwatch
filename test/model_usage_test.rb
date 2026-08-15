# frozen_string_literal: true

require_relative "test_helper"

class ModelUsageTest < Minitest::Test
  def build_event(**overrides)
    defaults = {
      message_id: "msg_1", model: "claude-sonnet-5", timestamp: Time.now, cwd: "/tmp",
      input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    }
    Aiwatch::UsageEvent.new(**defaults.merge(overrides))
  end

  def test_aggregates_multiple_events
    usage = Aiwatch::ModelUsage.new(model: "claude-sonnet-5")
    usage.add(build_event(input_tokens: 10, output_tokens: 5, cache_creation_1h_tokens: 100, cache_read_input_tokens: 20))
    usage.add(build_event(input_tokens: 3, output_tokens: 2, cache_creation_5m_tokens: 50, cache_read_input_tokens: 5))

    assert_equal 13, usage.input_tokens
    assert_equal 7, usage.output_tokens
    assert_equal 100, usage.cache_creation_1h_tokens
    assert_equal 50, usage.cache_creation_5m_tokens
    assert_equal 150, usage.cache_creation_tokens
    assert_equal 25, usage.cache_read_tokens
    assert_equal 2, usage.event_count
    assert_equal 13 + 7 + 150 + 25, usage.total_tokens
  end
end
