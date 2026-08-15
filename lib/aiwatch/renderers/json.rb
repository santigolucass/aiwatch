# frozen_string_literal: true

require "json"

module Aiwatch
  module Renderers
    # JSON output. Field names and shapes here are the documented --json
    # contract (see README) — changing them is a breaking change.
    class Json
      def initialize(cost_calculator)
        @cost_calculator = cost_calculator
      end

      def render_list(sessions, now: Time.now, active_threshold_minutes: 5)
        JSON.pretty_generate(sessions.map { |s| session_summary(s, now, active_threshold_minutes) })
      end

      def render_daily(daily_rows)
        JSON.pretty_generate(daily_rows.map do |day|
          {
            date: day[:date].to_s,
            session_count: day[:session_count],
            input_tokens: day[:input_tokens],
            output_tokens: day[:output_tokens],
            cache_read_tokens: day[:cache_read_tokens],
            cache_creation_tokens: day[:cache_creation_tokens],
            cost_usd: day[:cost].round(6),
            fully_known: day[:fully_known]
          }
        end)
      end

      def render_show(session, now: Time.now, active_threshold_minutes: 5)
        total = @cost_calculator.total_for(session)
        JSON.pretty_generate(
          session_summary(session, now, active_threshold_minutes).merge(
            models: session.model_usages.values.map { |usage| model_breakdown(usage) },
            unknown_models: total.unknown_models
          )
        )
      end

      private

      def session_summary(session, now, active_threshold_minutes)
        total = @cost_calculator.total_for(session)
        {
          session_id: session.id,
          project: session.project,
          models: session.models,
          input_tokens: session.total_input_tokens,
          output_tokens: session.total_output_tokens,
          cache_read_tokens: session.total_cache_read_tokens,
          cache_creation_tokens: session.total_cache_creation_tokens,
          cost_usd: total.amount.round(6),
          fully_known: total.fully_known?,
          first_activity: session.first_seen_at&.iso8601,
          last_activity: session.last_seen_at&.iso8601,
          active: session.active?(now: now, threshold_minutes: active_threshold_minutes)
        }
      end

      def model_breakdown(usage)
        cost = @cost_calculator.cost_for(usage)
        {
          model: usage.model,
          input_tokens: usage.input_tokens,
          output_tokens: usage.output_tokens,
          cache_read_tokens: usage.cache_read_tokens,
          cache_creation_tokens: usage.cache_creation_tokens,
          cost_usd: cost&.round(6)
        }
      end
    end
  end
end
