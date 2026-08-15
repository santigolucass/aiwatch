# frozen_string_literal: true

require "json"

module Aiwatch
  module Adapters
    # Parses Claude Code's local session transcripts, stored one JSONL file
    # per session under ~/.claude/projects/<project-slug>/<session-uuid>.jsonl.
    #
    # See docs/claude-code-format.md for the observed schema and the
    # reasoning behind the parsing rules below.
    class ClaudeCode < Base
      DEFAULT_DIR = File.expand_path("~/.claude/projects")

      def initialize(dir: DEFAULT_DIR)
        @dir = dir
      end

      def name
        "claude-code"
      end

      def discover_sessions
        session_files.filter_map { |path| parse_file(path) }.reject(&:empty?)
      end

      private

      def session_files
        Dir.glob(File.join(@dir, "*", "*.jsonl"))
      end

      def parse_file(path)
        id = File.basename(path, ".jsonl")
        session = Session.new(id: id, file_path: path)
        seen_message_ids = {}

        File.foreach(path, encoding: "UTF-8") do |line|
          line.strip!
          next if line.empty?

          obj = begin
            JSON.parse(line)
          rescue
            session.note_skipped_line
            next
          end

          event = UsageEvent.from_line(obj)
          next if event.nil?
          next if seen_message_ids.key?(event.message_id)

          seen_message_ids[event.message_id] = true
          session.add_event(event)
        end

        session
      rescue Errno::ENOENT, Errno::EACCES, IOError
        nil
      end
    end
  end
end
