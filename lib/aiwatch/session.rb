# frozen_string_literal: true

module Aiwatch
  # A single Claude Code session (one JSONL file), with token usage
  # aggregated per model.
  class Session
    attr_reader :id, :file_path, :model_usages, :first_seen_at, :last_seen_at, :skipped_lines

    def initialize(id:, file_path:)
      @id = id
      @file_path = file_path
      @model_usages = {}
      @cwd_counts = Hash.new(0)
      @first_seen_at = nil
      @last_seen_at = nil
      @skipped_lines = 0
    end

    def add_event(event)
      usage = (@model_usages[event.model] ||= ModelUsage.new(model: event.model))
      usage.add(event)
      @cwd_counts[event.cwd] += 1 if event.cwd
      @first_seen_at = event.timestamp if @first_seen_at.nil? || event.timestamp < @first_seen_at
      @last_seen_at = event.timestamp if @last_seen_at.nil? || event.timestamp > @last_seen_at
      self
    end

    def note_skipped_line
      @skipped_lines += 1
    end

    def models
      model_usages.keys
    end

    # Most frequent cwd across this session's events. A session normally
    # stays in one project; this is a defensive tie-breaker, not a guess.
    def project
      @cwd_counts.max_by { |_, count| count }&.first
    end

    def empty?
      model_usages.empty?
    end

    def total_input_tokens
      model_usages.values.sum(&:input_tokens)
    end

    def total_output_tokens
      model_usages.values.sum(&:output_tokens)
    end

    def total_cache_read_tokens
      model_usages.values.sum(&:cache_read_tokens)
    end

    def total_cache_creation_tokens
      model_usages.values.sum(&:cache_creation_tokens)
    end

    def active?(now: Time.now, threshold_minutes: 5)
      return false unless File.exist?(file_path)

      (now - File.mtime(file_path)) <= threshold_minutes * 60
    end

    def short_id(length = 8)
      id[0, length]
    end
  end
end
