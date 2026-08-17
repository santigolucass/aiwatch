# frozen_string_literal: true

require "time"
require_relative "feed_event"

module Aiwatch
  # Turns a stream of parsed Claude Code JSONL objects, fed in file order,
  # into a scrolling event feed plus a handful of "current state"
  # side-channel readers the dashboard's sidebar wants (context occupancy,
  # stop reason, turn duration, permission mode...).
  #
  # This is the one place in aiwatch that reads `message.content` — a
  # deliberate, documented reversal of this project's earlier "never
  # display conversation content" stance (see docs/decisions.md). It's
  # still 100% local; the difference is that it now reaches the screen
  # (and an export), not just cost math.
  #
  # Only the fields this project has actually verified on real session
  # files are read, and every access is nil-safe: this schema isn't
  # published and has changed across Claude Code versions before, and a
  # malformed or unexpected shape here must degrade to "no side-channel
  # update" rather than break the render loop.
  class FeedBuilder
    SNIPPET_LENGTH = 240

    attr_reader :ctx_tokens, :ctx_model, :ctx_input_tokens, :ctx_cache_read_tokens,
      :ctx_cache_creation_tokens, :ctx_output_tokens, :stop_reason, :turn_ms, :permission_mode,
      :cli_version, :effort, :compactions, :cache_miss_count

    def initialize(feed:)
      @feed = feed
      @pending_tools = []
      @pending_tools_at = nil
      @compactions = 0
      @cache_miss_count = 0
    end

    # obj: one parsed JSONL line, in file order. seen_message_ids: the
    # same dedup Hash LineFolder uses for usage totals, checked (but not
    # written) here so a streamed duplicate of an already-known message
    # doesn't narrate twice — call this BEFORE LineFolder.fold_object
    # marks the id seen, or every line will look like a repeat.
    def ingest(obj, seen_message_ids)
      case obj["type"]
      when "assistant" then ingest_assistant(obj, seen_message_ids)
      when "user" then ingest_user(obj)
      when "system" then ingest_system(obj)
      when "pr-link" then ingest_pr_link(obj)
      when "permission-mode" then @permission_mode = obj["permissionMode"] || @permission_mode
      end
      @cli_version = obj["version"] if obj["version"].is_a?(String)
    end

    # Flushes any tool-use cluster still buffered (e.g. at the end of a
    # tick's batch of newly-read lines) so it doesn't wait for an
    # unrelated line to trigger it.
    def flush!
      flush_tools
    end

    private

    def ingest_assistant(obj, seen_message_ids)
      message = obj["message"]
      return unless message.is_a?(Hash)

      update_side_channel(obj, message)

      message_id = message["id"]
      return if message_id && seen_message_ids.key?(message_id)

      block = Array(message["content"]).first
      return unless block.is_a?(Hash)

      at = parse_time(obj["timestamp"])
      case block["type"]
      when "tool_use"
        @pending_tools << (block["name"].is_a?(String) ? block["name"].split("__").last : "?")
        @pending_tools_at = at
      when "text"
        flush_tools
        text = block["text"].to_s
        push(at, :assistant, snippet(text)) unless text.strip.empty?
      end
    end

    def update_side_channel(obj, message)
      usage = message["usage"]
      if usage.is_a?(Hash)
        @ctx_input_tokens = usage["input_tokens"].to_i
        @ctx_cache_read_tokens = usage["cache_read_input_tokens"].to_i
        @ctx_cache_creation_tokens = usage["cache_creation_input_tokens"].to_i
        @ctx_output_tokens = usage["output_tokens"].to_i
        @ctx_tokens = @ctx_input_tokens + @ctx_cache_read_tokens + @ctx_cache_creation_tokens
        @ctx_model = message["model"]
      end
      @stop_reason = message["stop_reason"] if message["stop_reason"].is_a?(String)
      @effort = obj["effort"] if obj["effort"].is_a?(String)

      diagnostics = message["diagnostics"]
      @cache_miss_count += 1 if diagnostics.is_a?(Hash) && diagnostics["cache_miss_reason"]
    end

    def ingest_user(obj)
      at = parse_time(obj["timestamp"])
      flush_tools
      content = obj.dig("message", "content")
      case content
      when String
        push(at, :user, snippet(content)) unless content.strip.empty?
      when Array
        block = content.first
        push(at, :result, block["is_error"] ? "error" : "ok") if block.is_a?(Hash) && block["type"] == "tool_result"
      end
    end

    def ingest_system(obj)
      at = parse_time(obj["timestamp"])
      case obj["subtype"]
      when "turn_duration"
        @turn_ms = obj["durationMs"] if obj["durationMs"].is_a?(Numeric)
      when "compact_boundary"
        @compactions += 1
        meta = obj["compactMetadata"]
        pre = meta.is_a?(Hash) ? meta["preTokens"] : nil
        post = meta.is_a?(Hash) ? meta["postTokens"] : nil
        label = ([pre, post].all? { |v| v.is_a?(Numeric) }) ? "compacted #{pre}→#{post} tokens" : "compacted"
        push(at, :compact, label)
      end
    end

    def ingest_pr_link(obj)
      number = obj["prNumber"]
      push(parse_time(obj["timestamp"]), :pr, "PR ##{number}") if number
    end

    def flush_tools
      return if @pending_tools.empty?

      names = @pending_tools
      text = (names.length == 1) ? "Executed 1 tool: [#{names.first}]" : "Executed #{names.length} tools: [#{names.join(" -> ")}]"
      push(@pending_tools_at, :tool, text)
      @pending_tools = []
      @pending_tools_at = nil
    end

    def push(at, kind, text)
      @feed.push(FeedEvent.new(at, kind, text))
    end

    def snippet(text)
      text = text.strip
      (text.length > SNIPPET_LENGTH) ? "#{text[0, SNIPPET_LENGTH]}…" : text
    end

    def parse_time(value)
      return nil unless value.is_a?(String)

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
