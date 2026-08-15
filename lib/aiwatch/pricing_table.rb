# frozen_string_literal: true

require "json"
require "fileutils"
require "net/http"
require "uri"

module Aiwatch
  # Resolves per-token prices for a model, in three layers:
  #   1. A local cache (~/.cache/aiwatch/pricing.json), refreshed every 24h.
  #   2. A live fetch from LiteLLM's pricing table when the cache is stale
  #      or missing.
  #   3. A small snapshot bundled with the gem, used only when both the
  #      network and the cache are unavailable.
  #
  # Layer 3 (and a stale layer-1 fallback after a failed fetch) push a
  # message onto #warnings so callers can surface it to the user.
  class PricingTable
    LITELLM_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    DEFAULT_CACHE_PATH = File.expand_path("~/.cache/aiwatch/pricing.json")
    DEFAULT_SNAPSHOT_PATH = File.expand_path("../../data/pricing_snapshot.json", __dir__)
    TTL_SECONDS = 24 * 60 * 60

    DEFAULT_HTTP_GET = lambda do |url, open_timeout:, read_timeout:|
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      response = http.get(uri.request_uri)
      response.is_a?(Net::HTTPSuccess) ? response.body : nil
    rescue
      nil
    end

    attr_reader :warnings

    def initialize(cache_path: DEFAULT_CACHE_PATH, snapshot_path: DEFAULT_SNAPSHOT_PATH,
      url: LITELLM_URL, http_get: DEFAULT_HTTP_GET, open_timeout: 5, read_timeout: 10)
      @cache_path = cache_path
      @snapshot_path = snapshot_path
      @url = url
      @http_get = http_get
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @warnings = []
    end

    def prices
      @prices ||= load
    end

    def price_for(model)
      prices[model]
    end

    private

    def load
      if cache_fresh?
        cached = read_cache
        return cached if cached
      end

      fetched = fetch_remote
      if fetched
        write_cache(fetched)
        return fetched
      end

      cached = read_cache
      if cached
        @warnings << "Could not refresh pricing from the network; using cached prices from #{File.mtime(@cache_path)}."
        return cached
      end

      @warnings << "Could not fetch pricing or find a cache; using the bundled offline snapshot (prices may be outdated)."
      read_snapshot || {}
    end

    def cache_fresh?
      File.exist?(@cache_path) && (Time.now - File.mtime(@cache_path)) < TTL_SECONDS
    end

    def read_cache
      parse_json(File.read(@cache_path))
    rescue Errno::ENOENT
      nil
    end

    def write_cache(data)
      FileUtils.mkdir_p(File.dirname(@cache_path))
      File.write(@cache_path, JSON.generate(data))
    rescue
      nil # non-fatal: pricing still works this run, it just won't be cached
    end

    def fetch_remote
      body = @http_get.call(@url, open_timeout: @open_timeout, read_timeout: @read_timeout)
      body && parse_json(body)
    end

    def read_snapshot
      parse_json(File.read(@snapshot_path))
    rescue Errno::ENOENT
      nil
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
