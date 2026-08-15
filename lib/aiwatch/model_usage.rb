# frozen_string_literal: true

module Aiwatch
  # Token totals for a single model within a session.
  class ModelUsage
    attr_reader :model, :input_tokens, :output_tokens,
      :cache_creation_1h_tokens, :cache_creation_5m_tokens,
      :cache_read_tokens, :event_count

    def initialize(model:)
      @model = model
      @input_tokens = 0
      @output_tokens = 0
      @cache_creation_1h_tokens = 0
      @cache_creation_5m_tokens = 0
      @cache_read_tokens = 0
      @event_count = 0
    end

    def add(event)
      @input_tokens += event.input_tokens
      @output_tokens += event.output_tokens
      @cache_creation_1h_tokens += event.cache_creation_1h_tokens
      @cache_creation_5m_tokens += event.cache_creation_5m_tokens
      @cache_read_tokens += event.cache_read_input_tokens
      @event_count += 1
      self
    end

    def cache_creation_tokens
      cache_creation_1h_tokens + cache_creation_5m_tokens
    end

    def total_tokens
      input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens
    end
  end
end
