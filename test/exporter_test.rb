# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

class ExporterTest < Minitest::Test
  include SessionFactory

  def cost_calculator
    Aiwatch::CostCalculator.new(FakePricingTable.new("claude-sonnet-5" => {"input_cost_per_token" => 1e-6, "output_cost_per_token" => 2e-6}))
  end

  def live_session(id:, title:)
    session = build_session(id: id, input: 100, output: 50)
    session.set_title(title)
    Aiwatch::LiveSession.new(session: session)
  end

  def test_writes_json_by_default
    Dir.mktmpdir do |dir|
      path = File.join(dir, "export")
      sessions = [live_session(id: "aaaa1111", title: "Fix the bug")]
      Aiwatch::Exporter.write(sessions, cost_calculator: cost_calculator, path: path)
      data = JSON.parse(File.read(path))
      assert_equal 1, data.length
      assert_equal "Fix the bug", data.first["name"]
    end
  end

  def test_writes_csv_when_path_ends_in_csv
    Dir.mktmpdir do |dir|
      path = File.join(dir, "export.csv")
      sessions = [live_session(id: "aaaa1111", title: "Fix the bug")]
      Aiwatch::Exporter.write(sessions, cost_calculator: cost_calculator, path: path)
      lines = File.readlines(path)
      assert_equal "session_id,name,project,models,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,cost_usd,active,last_activity\n", lines.first
      assert_includes lines[1], "Fix the bug"
    end
  end

  def test_csv_escapes_commas_and_quotes_in_titles
    Dir.mktmpdir do |dir|
      path = File.join(dir, "export.csv")
      sessions = [live_session(id: "aaaa1111", title: 'Fix "the" bug, please')]
      Aiwatch::Exporter.write(sessions, cost_calculator: cost_calculator, path: path)
      content = File.read(path)
      assert_includes content, '"Fix ""the"" bug, please"'
    end
  end

  def test_returns_the_path_written
    Dir.mktmpdir do |dir|
      path = File.join(dir, "export.json")
      result = Aiwatch::Exporter.write([], cost_calculator: cost_calculator, path: path)
      assert_equal path, result
    end
  end
end
