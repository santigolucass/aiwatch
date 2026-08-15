# frozen_string_literal: true

require_relative "test_helper"

class DailyAggregatorTest < Minitest::Test
  PRICE = {
    "claude-sonnet-5" => {"input_cost_per_token" => 1e-6, "output_cost_per_token" => 0},
    "claude-opus-5" => {"input_cost_per_token" => 2e-6, "output_cost_per_token" => 0}
  }.freeze

  def build_event(model:, timestamp:, input_tokens: 0, message_id: "m-#{rand(1_000_000)}")
    Aiwatch::UsageEvent.new(
      message_id: message_id, model: model, timestamp: timestamp, cwd: "/x",
      input_tokens: input_tokens, output_tokens: 0, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    )
  end

  def calculator
    Aiwatch::CostCalculator.new(FakePricingTable.new(PRICE))
  end

  def test_aggregates_across_sessions_by_local_date
    day1 = Time.iso8601("2026-08-01T12:00:00Z")
    day2 = Time.iso8601("2026-08-02T12:00:00Z")

    session_a = Aiwatch::Session.new(id: "a", file_path: "/dev/null")
    session_a.add_event(build_event(model: "claude-sonnet-5", timestamp: day1, input_tokens: 1000))

    session_b = Aiwatch::Session.new(id: "b", file_path: "/dev/null")
    session_b.add_event(build_event(model: "claude-sonnet-5", timestamp: day1, input_tokens: 500))
    session_b.add_event(build_event(model: "claude-opus-5", timestamp: day2, input_tokens: 200))

    rows = Aiwatch::DailyAggregator.new(calculator).aggregate([session_a, session_b])
    by_date = rows.each_with_object({}) { |r, h| h[r[:date]] = r }

    row1 = by_date.fetch(day1.getlocal.to_date)
    assert_equal 2, row1[:session_count]
    assert_equal 1500, row1[:input_tokens]
    assert_in_delta 1500 * 1e-6, row1[:cost], 1e-9

    row2 = by_date.fetch(day2.getlocal.to_date)
    assert_equal 1, row2[:session_count]
    assert_equal 200, row2[:input_tokens]
  end

  def test_a_session_spanning_two_days_counts_once_per_day
    # 48h apart so the two events land on different local calendar dates
    # regardless of this machine's timezone offset.
    day1 = Time.iso8601("2026-08-01T12:00:00Z")
    day2 = Time.iso8601("2026-08-03T12:00:00Z")

    session = Aiwatch::Session.new(id: "a", file_path: "/dev/null")
    session.add_event(build_event(model: "claude-sonnet-5", timestamp: day1, input_tokens: 10))
    session.add_event(build_event(model: "claude-sonnet-5", timestamp: day2, input_tokens: 20))

    rows = Aiwatch::DailyAggregator.new(calculator).aggregate([session])

    assert_equal 2, rows.length
    assert(rows.all? { |r| r[:session_count] == 1 })
  end

  def test_rows_are_sorted_most_recent_date_first
    older = Time.iso8601("2026-08-01T12:00:00Z")
    newer = Time.iso8601("2026-08-03T12:00:00Z")

    session = Aiwatch::Session.new(id: "a", file_path: "/dev/null")
    session.add_event(build_event(model: "claude-sonnet-5", timestamp: older))
    session.add_event(build_event(model: "claude-sonnet-5", timestamp: newer))

    rows = Aiwatch::DailyAggregator.new(calculator).aggregate([session])

    assert_equal newer.getlocal.to_date, rows.first[:date]
    assert_equal older.getlocal.to_date, rows.last[:date]
  end

  def test_unknown_model_marks_day_as_not_fully_known_but_still_sums_known_cost
    day = Time.iso8601("2026-08-01T12:00:00Z")
    session = Aiwatch::Session.new(id: "a", file_path: "/dev/null")
    session.add_event(build_event(model: "claude-sonnet-5", timestamp: day, input_tokens: 1000))
    session.add_event(build_event(model: "mystery-model", timestamp: day, input_tokens: 500))

    rows = Aiwatch::DailyAggregator.new(calculator).aggregate([session])

    assert_equal 1, rows.length
    refute rows.first[:fully_known]
    assert_in_delta 1000 * 1e-6, rows.first[:cost], 1e-9
  end
end
