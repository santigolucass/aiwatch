# frozen_string_literal: true

require "test_helper"

class RingBufferTest < Minitest::Test
  def test_push_returns_self_for_chaining
    buf = Aiwatch::RingBuffer.new(3)
    assert_same buf, buf.push(1)
  end

  def test_drops_oldest_when_over_capacity
    buf = Aiwatch::RingBuffer.new(3)
    [1, 2, 3, 4, 5].each { |x| buf << x }
    assert_equal [3, 4, 5], buf.to_a
  end

  def test_length_and_empty
    buf = Aiwatch::RingBuffer.new(3)
    assert buf.empty?
    buf << 1
    refute buf.empty?
    assert_equal 1, buf.length
  end

  def test_last_without_argument
    buf = Aiwatch::RingBuffer.new(3)
    buf << 1
    buf << 2
    assert_equal 2, buf.last
  end

  def test_last_with_n
    buf = Aiwatch::RingBuffer.new(5)
    [1, 2, 3].each { |x| buf << x }
    assert_equal [2, 3], buf.last(2)
  end

  def test_is_enumerable
    buf = Aiwatch::RingBuffer.new(3)
    [1, 2, 3].each { |x| buf << x }
    assert_equal [2, 4, 6], buf.map { |x| x * 2 }
  end

  def test_rejects_non_positive_capacity
    assert_raises(ArgumentError) { Aiwatch::RingBuffer.new(0) }
  end
end
