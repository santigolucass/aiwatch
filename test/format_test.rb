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
end
