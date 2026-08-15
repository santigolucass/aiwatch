# frozen_string_literal: true

require "time"

module Aiwatch
  # One deduplicated assistant usage event parsed from a Claude Code session line.
  class UsageEvent
    SYNTHETIC_MODEL = "<synthetic>"

    attr_reader :message_id, :model, :timestamp, :cwd,
      :input_tokens, :output_tokens,
      :cache_creation_input_tokens, :cache_read_input_tokens,
      :cache_creation_1h_tokens, :cache_creation_5m_tokens

    # Returns a UsageEvent for an eligible assistant line, or nil to skip
    # (non-assistant lines, missing usage, synthetic placeholder messages).
    def self.from_line(obj)
      return nil unless obj.is_a?(Hash) && obj["type"] == "assistant"

      message = obj["message"]
      return nil unless message.is_a?(Hash)

      usage = message["usage"]
      return nil unless usage.is_a?(Hash)

      model = message["model"]
      return nil if model.nil? || model == SYNTHETIC_MODEL

      message_id = message["id"]
      return nil unless message_id

      timestamp = parse_timestamp(obj["timestamp"])
      return nil unless timestamp

      cache_creation_total = usage["cache_creation_input_tokens"].to_i
      cache_creation = usage["cache_creation"].is_a?(Hash) ? usage["cache_creation"] : {}
      one_hour = cache_creation["ephemeral_1h_input_tokens"].to_i
      five_min = cache_creation["ephemeral_5m_input_tokens"].to_i

      # Fall back to the cheaper 5m rate whenever the TTL breakdown is
      # missing or doesn't reconcile with the reported total.
      unless one_hour + five_min == cache_creation_total
        one_hour = 0
        five_min = cache_creation_total
      end

      new(
        message_id: message_id,
        model: model,
        timestamp: timestamp,
        cwd: obj["cwd"],
        input_tokens: usage["input_tokens"].to_i,
        output_tokens: usage["output_tokens"].to_i,
        cache_creation_input_tokens: cache_creation_total,
        cache_read_input_tokens: usage["cache_read_input_tokens"].to_i,
        cache_creation_1h_tokens: one_hour,
        cache_creation_5m_tokens: five_min
      )
    end

    def self.parse_timestamp(value)
      return nil unless value.is_a?(String)

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
    private_class_method :parse_timestamp

    def initialize(message_id:, model:, timestamp:, cwd:, input_tokens:, output_tokens:,
      cache_creation_input_tokens:, cache_read_input_tokens:,
      cache_creation_1h_tokens:, cache_creation_5m_tokens:)
      @message_id = message_id
      @model = model
      @timestamp = timestamp
      @cwd = cwd
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @cache_creation_input_tokens = cache_creation_input_tokens
      @cache_read_input_tokens = cache_read_input_tokens
      @cache_creation_1h_tokens = cache_creation_1h_tokens
      @cache_creation_5m_tokens = cache_creation_5m_tokens
    end
  end
end
