# frozen_string_literal: true

require_relative "../test_helper"
require "tempfile"

class RenderersTableTest < Minitest::Test
  include SessionFactory

  PRICE = {
    "claude-sonnet-5" => {
      "input_cost_per_token" => 1e-6, "output_cost_per_token" => 2e-6,
      "cache_read_input_token_cost" => 0, "cache_creation_input_token_cost" => 0,
      "cache_creation_input_token_cost_above_1hr" => 0
    }
  }.freeze

  def calculator(prices = PRICE)
    Aiwatch::CostCalculator.new(FakePricingTable.new(prices))
  end

  def test_render_list_includes_headers_and_row_data
    session = build_session(input: 1000, output: 500)
    table = Aiwatch::Renderers::Table.new(calculator).render_list([session])

    assert_includes table, "SESSION"
    assert_includes table, "PROJECT"
    assert_includes table, "aaaaaaaa"
    assert_includes table, "/home/x/project"
    assert_includes table, "claude-sonnet-5"
    assert_includes table, "$0.0020" # 1000*1e-6 + 500*2e-6
  end

  def test_render_list_shows_question_mark_for_unknown_model_cost
    session = build_session(model: "totally-unknown")
    table = Aiwatch::Renderers::Table.new(calculator({})).render_list([session])

    assert_includes table, "?"
  end

  def test_active_session_id_is_colored_green_when_color_enabled
    Tempfile.create("aiwatch-active") do |active_file|
      Tempfile.create("aiwatch-stale") do |stale_file|
        File.utime(Time.now, Time.now, active_file.path)
        File.utime(Time.now - 3600, Time.now - 3600, stale_file.path)

        active = build_session(id: "1" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: active_file.path)
        stale = build_session(id: "2" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: stale_file.path)

        table = Aiwatch::Renderers::Table.new(calculator).render_list([active, stale], color: true)

        assert_includes table, "\e[1;32m11111111\e[0m"
        refute_includes table, "\e[1;32m22222222\e[0m"
        assert_includes table, "22222222"
      end
    end
  end

  def test_no_ansi_color_when_color_disabled_even_for_active_sessions
    Tempfile.create("aiwatch-active") do |active_file|
      File.utime(Time.now, Time.now, active_file.path)
      active = build_session(id: "33333333-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: active_file.path)

      table = Aiwatch::Renderers::Table.new(calculator).render_list([active], color: false)

      refute_includes table, "\e["
      assert_includes table, "33333333"
    end
  end

  def test_list_columns_stay_aligned_regardless_of_active_status
    Tempfile.create("aiwatch-active") do |active_file|
      Tempfile.create("aiwatch-stale") do |stale_file|
        File.utime(Time.now, Time.now, active_file.path)
        File.utime(Time.now - 3600, Time.now - 3600, stale_file.path)

        active = build_session(id: "1" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: active_file.path, input: 1000)
        stale = build_session(id: "2" * 8 + "-bbbb-cccc-dddd-eeeeeeeeeeee", file_path: stale_file.path, input: 1000)

        table = Aiwatch::Renderers::Table.new(calculator).render_list([active, stale], color: true)
        data_rows = table.lines.map(&:rstrip)[1..] # skip the header row, which has no "$"

        # The COST column must start at the same visible column on every
        # data row, whether or not that row's session id carries ANSI
        # color — this is the exact bug an ambiguous-width marker glyph
        # caused.
        cost_columns = data_rows.map { |l| Aiwatch::Renderers::TextTable.visible_length(l.split("$").first) }
        assert_equal 1, cost_columns.uniq.length
      end
    end
  end

  def test_render_daily_formats_rows
    day = {date: "2026-08-10", session_count: 3, input_tokens: 1500, output_tokens: 500,
           cache_read_tokens: 0, cache_creation_tokens: 0, cost: 1.5, fully_known: true}

    table = Aiwatch::Renderers::Table.new(calculator).render_daily([day])

    assert_includes table, "DATE"
    assert_includes table, "2026-08-10"
    assert_includes table, "1.5K"
    assert_includes table, "$1.5000"
  end

  def test_render_show_lists_model_breakdown_and_warns_on_unknown_models
    session = Aiwatch::Session.new(id: "s1", file_path: "/dev/null")
    session.add_event(Aiwatch::UsageEvent.new(
      message_id: "m1", model: "claude-sonnet-5", timestamp: Time.now, cwd: "/x",
      input_tokens: 100, output_tokens: 50, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    ))
    session.add_event(Aiwatch::UsageEvent.new(
      message_id: "m2", model: "mystery-model", timestamp: Time.now, cwd: "/x",
      input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0, cache_creation_1h_tokens: 0, cache_creation_5m_tokens: 0
    ))

    text = Aiwatch::Renderers::Table.new(calculator).render_show(session)

    assert_includes text, "claude-sonnet-5"
    assert_includes text, "mystery-model"
    assert_includes text, "Warning: no pricing data for: mystery-model"
  end
end
