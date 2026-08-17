# frozen_string_literal: true

require_relative "test_helper"

class FormatTest < Minitest::Test
  def test_tokens_below_1000_are_shown_verbatim
    assert_equal "0", Aiwatch::Format.tokens(0)
    assert_equal "500", Aiwatch::Format.tokens(500)
  end

  def test_tokens_in_thousands_use_k_suffix
    assert_equal "1.5K", Aiwatch::Format.tokens(1500)
    assert_equal "2K", Aiwatch::Format.tokens(2000)
  end

  def test_tokens_in_millions_use_m_suffix
    assert_equal "1.2M", Aiwatch::Format.tokens(1_234_567)
  end

  def test_cost_formats_to_four_decimals
    assert_equal "$0.1234", Aiwatch::Format.cost(0.1234)
  end

  def test_cost_renders_question_mark_when_unknown_or_nil
    assert_equal "?", Aiwatch::Format.cost(1.0, unknown: true)
    assert_equal "?", Aiwatch::Format.cost(nil)
  end

  def test_relative_time_buckets
    now = Time.now
    assert_equal "just now", Aiwatch::Format.relative_time(now - 30, now: now)
    assert_equal "2m ago", Aiwatch::Format.relative_time(now - 125, now: now)
    assert_equal "2h ago", Aiwatch::Format.relative_time(now - 7200, now: now)
    assert_equal "2d ago", Aiwatch::Format.relative_time(now - (2 * 86_400), now: now)
    assert_equal (now - (10 * 86_400)).strftime("%Y-%m-%d"), Aiwatch::Format.relative_time(now - (10 * 86_400), now: now)
  end

  def test_relative_time_nil_is_a_dash
    assert_equal "-", Aiwatch::Format.relative_time(nil)
  end

  def test_uptime_buckets
    now = Time.now
    assert_equal "45s", Aiwatch::Format.uptime(now - 45, now: now)
    assert_equal "5m", Aiwatch::Format.uptime(now - 300, now: now)
    assert_equal "3h", Aiwatch::Format.uptime(now - 10_800, now: now)
    assert_equal "2d", Aiwatch::Format.uptime(now - (2 * 86_400), now: now)
  end

  def test_uptime_nil_or_future_is_a_dash
    now = Time.now
    assert_equal "-", Aiwatch::Format.uptime(nil)
    assert_equal "-", Aiwatch::Format.uptime(now + 10, now: now)
  end

  def test_duration_ms
    assert_equal "1.5s", Aiwatch::Format.duration_ms(1500)
    assert_equal "2m", Aiwatch::Format.duration_ms(120_000)
    assert_equal "-", Aiwatch::Format.duration_ms(nil)
  end

  def test_percent
    assert_equal "42%", Aiwatch::Format.percent(0.42)
    assert_equal "?", Aiwatch::Format.percent(nil)
  end

  def test_count_adds_thousands_separators
    assert_equal "1,063,958", Aiwatch::Format.count(1_063_958)
    assert_equal "42", Aiwatch::Format.count(42)
    assert_equal "0", Aiwatch::Format.count(nil)
  end

  def test_clock_formats_time
    t = Time.new(2026, 8, 17, 9, 9, 0)
    assert_equal "09:09:00", Aiwatch::Format.clock(t)
    assert_equal "--:--:--", Aiwatch::Format.clock(nil)
  end

  def test_short_path_truncates_from_the_left
    result = Aiwatch::Format.short_path("/home/lucas/code/aiwatch/lib/foo.rb", 20)
    assert_equal 20, result.length
    assert result.end_with?("foo.rb")
  end

  def test_short_path_nil_is_a_question_mark
    assert_equal "?", Aiwatch::Format.short_path(nil, 20)
  end
end
