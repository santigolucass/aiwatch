# frozen_string_literal: true

require "test_helper"

class ContextWindowTest < Minitest::Test
  CW = Aiwatch::ContextWindow

  def test_returns_nil_without_a_limit
    assert_nil CW.breakdown(input: 1, cache_write: 1, cache_read: 1, output: 1, limit: nil)
    assert_nil CW.breakdown(input: 1, cache_write: 1, cache_read: 1, output: 1, limit: 0)
  end

  def test_computes_percentages_against_the_limit
    b = CW.breakdown(input: 100, cache_write: 200, cache_read: 300, output: 400, limit: 1000)
    assert_in_delta 10.0, b.input_pct
    assert_in_delta 20.0, b.cache_write_pct
    assert_in_delta 30.0, b.cache_read_pct
    assert_in_delta 40.0, b.output_pct
    assert_in_delta 0.0, b.free_pct
    assert_equal 1000, b.occupied
  end

  def test_free_fills_the_remainder
    b = CW.breakdown(input: 10, cache_write: 0, cache_read: 0, output: 0, limit: 100)
    assert_in_delta 90.0, b.free_pct
  end

  def test_free_never_goes_negative_when_occupied_exceeds_limit
    b = CW.breakdown(input: 2_000, cache_write: 0, cache_read: 0, output: 0, limit: 1_000)
    assert_in_delta 0.0, b.free_pct
  end

  def test_nil_components_are_treated_as_zero
    b = CW.breakdown(input: nil, cache_write: nil, cache_read: nil, output: nil, limit: 100)
    assert_in_delta 100.0, b.free_pct
    assert_equal 0, b.occupied
  end
end
