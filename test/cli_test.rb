# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  def test_version_flag
    out, = capture_io { @code = Aiwatch::CLI.run(["--version"]) }

    assert_equal 0, @code
    assert_includes out, Aiwatch::VERSION
  end

  def test_help_flag
    out, = capture_io { @code = Aiwatch::CLI.run(["--help"]) }

    assert_equal 0, @code
    assert_includes out, "Usage: aiwatch"
    assert_includes out, "daily"
  end

  def test_unknown_since_format_prints_error_and_returns_nonzero
    _, err = capture_io do
      @code = Aiwatch::CLI.run(["list", "--dir", "/nonexistent-for-tests", "--since", "banana"])
    end

    assert_equal 1, @code
    assert_includes err, "--since"
  end
end
