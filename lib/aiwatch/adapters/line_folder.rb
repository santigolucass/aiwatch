# frozen_string_literal: true

require "json"

module Aiwatch
  module Adapters
    # Folds one Claude Code JSONL line into a Session: title updates and
    # deduplicated usage events. Extracted out of ClaudeCode#parse_file so
    # SessionStore's incremental reader can fold freshly-tailed lines
    # through the exact same rules a full-file parse uses, without
    # re-implementing them.
    #
    # `fold_object` is the reusable core (takes an already-parsed Hash);
    # `fold` additionally parses a raw JSON line and accounts a malformed
    # one via Session#note_skipped_line, matching what a full-file parse
    # has always done.
    module LineFolder
      module_function

      def fold(session, seen_message_ids, raw_line)
        line = raw_line.strip
        return true if line.empty?

        obj = begin
          JSON.parse(line)
        rescue
          session.note_skipped_line
          return false
        end

        fold_object(session, seen_message_ids, obj)
        true
      end

      def fold_object(session, seen_message_ids, obj)
        if obj["type"] == "ai-title"
          session.set_title(obj["aiTitle"])
          return
        end

        event = UsageEvent.from_line(obj)
        return if event.nil?
        return if seen_message_ids.key?(event.message_id)

        seen_message_ids[event.message_id] = true
        session.add_event(event)
      end
    end
  end
end
