# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "aiwatch"
require "minitest/autorun"

module FixturePath
  def fixture_path(*segments)
    File.join(__dir__, "fixtures", *segments)
  end
end

class FakePricingTable
  def initialize(prices = {})
    @prices = prices
  end

  def price_for(model)
    @prices[model]
  end

  def context_limit_for(model)
    entry = @prices[model]
    entry && entry["max_input_tokens"]
  end

  attr_reader :prices

  def warnings
    []
  end
end

module SessionFactory
  def build_session(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: File::NULL,
    model: "claude-sonnet-5", input: 1000, output: 500, cache_read: 0,
    cache_1h: 0, cache_5m: 0, timestamp: Time.now, project: "/home/x/project")
    session = Aiwatch::Session.new(id: id, file_path: file_path)
    session.add_event(Aiwatch::UsageEvent.new(
      message_id: "m-#{rand(1_000_000)}", model: model, timestamp: timestamp, cwd: project,
      input_tokens: input, output_tokens: output, cache_creation_input_tokens: cache_1h + cache_5m,
      cache_read_input_tokens: cache_read, cache_creation_1h_tokens: cache_1h, cache_creation_5m_tokens: cache_5m
    ))
    session
  end
end
