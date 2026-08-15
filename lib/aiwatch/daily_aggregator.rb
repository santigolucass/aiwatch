# frozen_string_literal: true

require "set"

module Aiwatch
  # Rolls sessions' per-(date, model) usage up into one row per local
  # calendar day across all sessions. A session can contribute to more than
  # one day; session_count counts each session once per day it touched.
  class DailyAggregator
    Bucket = Struct.new(:session_ids, :input, :output, :cache_read, :cache_creation, :cost, :unknown_models) do
      def self.empty
        new(Set.new, 0, 0, 0, 0, 0.0, Set.new)
      end
    end
    private_constant :Bucket

    def initialize(cost_calculator)
      @cost_calculator = cost_calculator
    end

    def aggregate(sessions)
      by_date = Hash.new { |h, k| h[k] = Bucket.empty }

      sessions.each do |session|
        session.daily_usages.each do |(date, model), usage|
          bucket = by_date[date]
          bucket.session_ids << session.id
          bucket.input += usage.input_tokens
          bucket.output += usage.output_tokens
          bucket.cache_read += usage.cache_read_tokens
          bucket.cache_creation += usage.cache_creation_tokens

          cost = @cost_calculator.cost_for(usage)
          if cost
            bucket.cost += cost
          else
            bucket.unknown_models << model
          end
        end
      end

      by_date.map { |date, b| row(date, b) }.sort_by { |r| r[:date] }.reverse
    end

    private

    def row(date, bucket)
      {
        date: date,
        session_count: bucket.session_ids.size,
        input_tokens: bucket.input,
        output_tokens: bucket.output,
        cache_read_tokens: bucket.cache_read,
        cache_creation_tokens: bucket.cache_creation,
        cost: bucket.cost,
        fully_known: bucket.unknown_models.empty?
      }
    end
  end
end
