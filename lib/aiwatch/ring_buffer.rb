# frozen_string_literal: true

module Aiwatch
  # A bounded FIFO: pushing past capacity silently drops the oldest entry.
  # Replaces the `history << x; history.shift while history.length > n`
  # idiom that used to live inline in the live renderer.
  class RingBuffer
    include Enumerable

    def initialize(capacity)
      raise ArgumentError, "capacity must be positive" unless capacity.positive?

      @capacity = capacity
      @items = []
    end

    def push(item)
      @items << item
      @items.shift while @items.length > @capacity
      self
    end
    alias_method :<<, :push

    def to_a
      @items.dup
    end

    def each(&block)
      return enum_for(:each) unless block

      @items.each(&block)
    end

    def length
      @items.length
    end
    alias_method :size, :length

    def empty?
      @items.empty?
    end

    def last(n = nil)
      n.nil? ? @items.last : @items.last(n)
    end
  end
end
