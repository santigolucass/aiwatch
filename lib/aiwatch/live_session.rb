# frozen_string_literal: true

require "forwardable"
require_relative "feed_builder"
require_relative "ring_buffer"

module Aiwatch
  # Decorates a Session with everything the live dashboard needs that
  # Session itself must not know about — process stats, git branch, the
  # scrolling feed, context occupancy, and the small history ring buffers
  # behind CPU-HIST/MEM/token sparklines. Keeping this separate is what
  # lets Session stay exactly as simple as `list`/`daily`/`show` need it.
  class LiveSession
    extend Forwardable

    def_delegators :@session, :id, :short_id, :file_path, :project, :models,
      :total_input_tokens, :total_output_tokens, :total_cache_read_tokens, :total_cache_creation_tokens,
      :first_seen_at, :last_seen_at, :model_usages, :active?

    attr_reader :session, :feed, :cpu_history, :mem_history, :token_history, :parent_id, :agent_id
    attr_accessor :pid, :cpu_percent, :mem_percent, :branch, :dead, :totals_partial, :pinned, :color_index, :agent_type

    # parent_id/agent_id are both nil for a top-level session. A subagent
    # (spawned via the Agent tool, its own transcript nested under
    # ~/.claude/projects/<slug>/<parent-uuid>/subagents/agent-<agent_id>.jsonl,
    # possibly under another subagent rather than directly under a
    # top-level session — spawnDepth in its .meta.json can be > 1) sets
    # parent_id to whichever session spawned it and agent_id to the hex
    # id in its own filename. Its title (there's no ai-title line in a
    # subagent's own transcript to get one from) is set directly by
    # SessionStore from that same .meta.json's description field.
    def initialize(session:, feed_capacity: 200, history_capacity: 40, parent_id: nil, agent_id: nil)
      @session = session
      @feed = RingBuffer.new(feed_capacity)
      @feed_builder = FeedBuilder.new(feed: @feed)
      @cpu_history = RingBuffer.new(history_capacity)
      @mem_history = RingBuffer.new(history_capacity)
      @token_history = RingBuffer.new(history_capacity)
      @pid = nil
      @cpu_percent = nil
      @mem_percent = nil
      @branch = nil
      @dead = false
      @totals_partial = false
      @pinned = false
      @color_index = nil
      @parent_id = parent_id
      @agent_id = agent_id
      @title_override = nil
      @agent_type = nil
    end

    def subagent?
      !@parent_id.nil?
    end

    def title
      @title_override || @session.title
    end

    def title=(value)
      @title_override = value
    end

    def ingest(obj, seen_message_ids)
      @feed_builder.ingest(obj, seen_message_ids)
    end

    def flush_feed!
      @feed_builder.flush!
    end

    def ctx_tokens
      @feed_builder.ctx_tokens
    end

    def ctx_model
      @feed_builder.ctx_model
    end

    def ctx_input_tokens
      @feed_builder.ctx_input_tokens
    end

    def ctx_cache_read_tokens
      @feed_builder.ctx_cache_read_tokens
    end

    def ctx_cache_creation_tokens
      @feed_builder.ctx_cache_creation_tokens
    end

    def ctx_output_tokens
      @feed_builder.ctx_output_tokens
    end

    def stop_reason
      @feed_builder.stop_reason
    end

    def turn_ms
      @feed_builder.turn_ms
    end

    def permission_mode
      @feed_builder.permission_mode
    end

    def cli_version
      @feed_builder.cli_version
    end

    def effort
      @feed_builder.effort
    end

    def compactions
      @feed_builder.compactions
    end

    def dead?
      @dead
    end

    def pinned?
      @pinned
    end

    def totals_partial?
      @totals_partial
    end
  end
end
