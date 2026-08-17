# frozen_string_literal: true

require "test_helper"

class AdaptersLineFolderTest < Minitest::Test
  LineFolder = Aiwatch::Adapters::LineFolder

  def new_session
    Aiwatch::Session.new(id: "s1", file_path: File::NULL)
  end

  def assistant_line(id, tokens)
    {
      "type" => "assistant",
      "timestamp" => "2026-08-17T09:00:00.000Z", "cwd" => "/x",
      "message" => {"id" => id, "model" => "claude-sonnet-5", "usage" => {"input_tokens" => 1, "output_tokens" => tokens}}
    }.to_json
  end

  def test_fold_parses_and_accounts_a_usage_event
    session = new_session
    LineFolder.fold(session, {}, assistant_line("m1", 100))
    assert_equal 100, session.total_output_tokens
  end

  def test_fold_dedupes_by_message_id
    session = new_session
    seen = {}
    LineFolder.fold(session, seen, assistant_line("m1", 100))
    LineFolder.fold(session, seen, assistant_line("m1", 999))
    assert_equal 100, session.total_output_tokens
  end

  def test_fold_sets_title_from_ai_title_lines
    session = new_session
    LineFolder.fold(session, {}, {"type" => "ai-title", "aiTitle" => "Fix the bug"}.to_json)
    assert_equal "Fix the bug", session.title
  end

  def test_fold_counts_malformed_json_as_skipped_and_returns_false
    session = new_session
    result = LineFolder.fold(session, {}, "{not json")
    refute result
    assert_equal 1, session.skipped_lines
  end

  def test_fold_returns_true_for_a_blank_line
    session = new_session
    assert LineFolder.fold(session, {}, "   ")
  end

  def test_fold_object_skips_non_assistant_lines_without_error
    session = new_session
    LineFolder.fold_object(session, {}, {"type" => "system", "subtype" => "turn_duration"})
    assert session.empty?
  end
end
