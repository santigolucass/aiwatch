# frozen_string_literal: true

module Aiwatch
  # Writes a snapshot of the dashboard's currently visible sessions to a
  # file — JSON (reusing the documented `--json` shape via Renderers::Json)
  # or CSV. Format is inferred from the path's extension; `.csv` gets CSV,
  # anything else gets JSON.
  #
  # CSV is hand-rolled rather than `require "csv"`: as of Ruby 3.4, `csv`
  # is a bundled gem, not a default one — assuming it's installed would
  # quietly break this project's zero-runtime-dependency guarantee for
  # anyone whose Ruby doesn't happen to have it. The quoting rules below
  # are the whole of RFC 4180 this export actually needs.
  module Exporter
    module_function

    def write(live_sessions, cost_calculator:, path:, now: Time.now, active_threshold_minutes: 5)
      sessions = live_sessions.map(&:session)
      content = path.end_with?(".csv") ? to_csv(sessions, cost_calculator, now, active_threshold_minutes) : to_json(sessions, cost_calculator, now, active_threshold_minutes)
      File.write(path, content)
      path
    end

    def to_json(sessions, cost_calculator, now, active_threshold_minutes)
      Renderers::Json.new(cost_calculator).render_list(sessions, now: now, active_threshold_minutes: active_threshold_minutes)
    end

    def to_csv(sessions, cost_calculator, now, active_threshold_minutes)
      headers = %w[session_id name project models input_tokens output_tokens cache_read_tokens
        cache_creation_tokens cost_usd active last_activity]
      rows = sessions.map { |s| csv_row(s, cost_calculator, now, active_threshold_minutes) }
      ([headers] + rows).map { |row| row.map { |cell| csv_escape(cell) }.join(",") }.join("\n") + "\n"
    end

    def csv_row(session, cost_calculator, now, active_threshold_minutes)
      total = cost_calculator.total_for(session)
      [
        session.id, session.title, session.project, session.models.join("|"),
        session.total_input_tokens, session.total_output_tokens,
        session.total_cache_read_tokens, session.total_cache_creation_tokens,
        format("%.6f", total.amount || 0),
        session.active?(now: now, threshold_minutes: active_threshold_minutes),
        session.last_seen_at&.iso8601
      ]
    end

    def csv_escape(value)
      text = value.to_s
      text.match?(/[",\n]/) ? "\"#{text.gsub('"', '""')}\"" : text
    end
  end
end
