# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"
require "tmpdir"

class PricingTableTest < Minitest::Test
  FRESH_PRICES = {"model-a" => {"input_cost_per_token" => 1.0}}.freeze
  FETCHED_PRICES = {"model-b" => {"input_cost_per_token" => 2.0}}.freeze
  SNAPSHOT_PRICES = {"model-c" => {"input_cost_per_token" => 3.0}}.freeze

  def with_tmp_paths
    Dir.mktmpdir do |dir|
      cache_path = File.join(dir, "pricing.json")
      snapshot_path = File.join(dir, "snapshot.json")
      File.write(snapshot_path, JSON.generate(SNAPSHOT_PRICES))
      yield cache_path, snapshot_path
    end
  end

  def build(cache_path:, snapshot_path:, http_get:)
    Aiwatch::PricingTable.new(cache_path: cache_path, snapshot_path: snapshot_path, http_get: http_get)
  end

  def failing_http_get
    ->(_url, open_timeout:, read_timeout:) { nil }
  end

  def test_uses_fresh_cache_without_hitting_the_network
    with_tmp_paths do |cache_path, snapshot_path|
      File.write(cache_path, JSON.generate(FRESH_PRICES))

      calls = 0
      http_get = ->(*) { calls += 1; nil }
      table = build(cache_path: cache_path, snapshot_path: snapshot_path, http_get: http_get)

      assert_equal FRESH_PRICES, table.prices
      assert_equal 0, calls
      assert_empty table.warnings
    end
  end

  def test_fetches_and_writes_cache_when_no_cache_exists
    with_tmp_paths do |cache_path, snapshot_path|
      http_get = ->(*) { JSON.generate(FETCHED_PRICES) }
      table = build(cache_path: cache_path, snapshot_path: snapshot_path, http_get: http_get)

      assert_equal FETCHED_PRICES, table.prices
      assert_equal FETCHED_PRICES, JSON.parse(File.read(cache_path))
      assert_empty table.warnings
    end
  end

  def test_refreshes_a_stale_cache_from_the_network
    with_tmp_paths do |cache_path, snapshot_path|
      File.write(cache_path, JSON.generate(FRESH_PRICES))
      File.utime(Time.now - (25 * 60 * 60), Time.now - (25 * 60 * 60), cache_path)

      http_get = ->(*) { JSON.generate(FETCHED_PRICES) }
      table = build(cache_path: cache_path, snapshot_path: snapshot_path, http_get: http_get)

      assert_equal FETCHED_PRICES, table.prices
    end
  end

  def test_falls_back_to_stale_cache_when_fetch_fails
    with_tmp_paths do |cache_path, snapshot_path|
      File.write(cache_path, JSON.generate(FRESH_PRICES))
      File.utime(Time.now - (25 * 60 * 60), Time.now - (25 * 60 * 60), cache_path)

      table = build(cache_path: cache_path, snapshot_path: snapshot_path, http_get: failing_http_get)

      assert_equal FRESH_PRICES, table.prices
      refute_empty table.warnings
    end
  end

  def test_falls_back_to_embedded_snapshot_when_fetch_and_cache_both_fail
    with_tmp_paths do |cache_path, snapshot_path|
      table = build(cache_path: cache_path, snapshot_path: snapshot_path, http_get: failing_http_get)

      assert_equal SNAPSHOT_PRICES, table.prices
      refute_empty table.warnings
    end
  end

  def test_price_for_returns_nil_for_unknown_model
    with_tmp_paths do |cache_path, snapshot_path|
      http_get = ->(*) { JSON.generate(FETCHED_PRICES) }
      table = build(cache_path: cache_path, snapshot_path: snapshot_path, http_get: http_get)

      assert_nil table.price_for("does-not-exist")
      refute_nil table.price_for("model-b")
    end
  end
end
