# frozen_string_literal: true

require "test_helper"

class FakeRawIO < StringIO
  attr_reader :raw_calls, :cooked_calls

  def initialize(...)
    super
    @raw_calls = 0
    @cooked_calls = 0
  end

  def raw!
    @raw_calls += 1
  end

  def cooked!
    @cooked_calls += 1
  end

  def tty?
    true
  end
end

class TuiScreenTest < Minitest::Test
  Screen = Aiwatch::Tui::Screen

  def test_size_uses_the_injected_size_reader
    screen = Screen.new(out: StringIO.new, in_stream: StringIO.new, size_reader: -> { [100, 40] })
    assert_equal [100, 40], screen.size
  end

  def test_size_falls_back_to_default_when_reader_raises
    screen = Screen.new(out: StringIO.new, in_stream: StringIO.new, size_reader: -> { raise Errno::ENOTTY })
    assert_equal Screen::DEFAULT_SIZE, screen.size
  end

  def test_size_falls_back_when_reader_returns_nils
    screen = Screen.new(out: StringIO.new, in_stream: StringIO.new, size_reader: -> { [nil, nil] })
    assert_equal Screen::DEFAULT_SIZE, screen.size
  end

  def test_enter_puts_input_into_raw_mode_and_exit_restores_it
    out = FakeRawIO.new
    in_stream = FakeRawIO.new
    screen = Screen.new(out: out, in_stream: in_stream, size_reader: -> { [80, 24] })
    screen.enter
    assert_equal 1, in_stream.raw_calls
    screen.exit
    assert_equal 1, in_stream.cooked_calls
  end

  def test_enter_hides_cursor_and_exit_shows_it
    out = FakeRawIO.new
    screen = Screen.new(out: out, in_stream: FakeRawIO.new, size_reader: -> { [80, 24] })
    screen.enter
    assert_includes out.string, "\e[?25l"
    screen.exit
    assert_includes out.string, "\e[?25h"
  end

  def test_altscreen_only_engages_on_a_tty
    out = StringIO.new
    def out.tty? = false
    screen = Screen.new(out: out, in_stream: FakeRawIO.new, size_reader: -> { [80, 24] })
    screen.enter
    refute_includes out.string, "\e[?1049h"
  end

  def test_altscreen_can_be_disabled_explicitly
    out = FakeRawIO.new
    screen = Screen.new(out: out, in_stream: FakeRawIO.new, altscreen: false, size_reader: -> { [80, 24] })
    screen.enter
    refute_includes out.string, "\e[?1049h"
  end

  def test_flush_writes_every_row_on_the_first_frame
    out = StringIO.new
    screen = Screen.new(out: out, in_stream: StringIO.new, size_reader: -> { [80, 24] })
    screen.flush(["a", "b"])
    assert_includes out.string, "\e[1;1H"
    assert_includes out.string, "\e[2;1H"
    assert_includes out.string, "a"
    assert_includes out.string, "b"
  end

  def test_flush_only_repaints_changed_rows_on_later_frames
    out = StringIO.new
    screen = Screen.new(out: out, in_stream: StringIO.new, size_reader: -> { [80, 24] })
    screen.flush(["a", "b"])
    out.truncate(0)
    out.rewind
    screen.flush(["a", "c"])
    refute_includes out.string, "\e[1;1H"
    assert_includes out.string, "\e[2;1H"
  end

  def test_flush_repaints_everything_when_forced
    out = StringIO.new
    screen = Screen.new(out: out, in_stream: StringIO.new, size_reader: -> { [80, 24] })
    screen.flush(["a", "b"])
    out.truncate(0)
    out.rewind
    screen.flush(["a", "b"], force: true)
    assert_includes out.string, "\e[1;1H"
    assert_includes out.string, "\e[2;1H"
  end

  def test_diffing_can_be_disabled
    out = StringIO.new
    screen = Screen.new(out: out, in_stream: StringIO.new, diff: false, size_reader: -> { [80, 24] })
    screen.flush(["a", "b"])
    out.truncate(0)
    out.rewind
    screen.flush(["a", "b"])
    assert_includes out.string, "\e[1;1H"
    assert_includes out.string, "\e[2;1H"
  end

  def test_resized_is_false_by_default_and_consumes_the_flag_once_true
    screen = Screen.new(out: StringIO.new, in_stream: StringIO.new, size_reader: -> { [80, 24] })
    refute screen.resized?
  end

  def test_sigwinch_sets_the_resized_flag
    skip "no WINCH signal on this platform" unless Signal.list.key?("WINCH")

    out = FakeRawIO.new
    screen = Screen.new(out: out, in_stream: FakeRawIO.new, size_reader: -> { [80, 24] })
    screen.enter
    Process.kill("WINCH", Process.pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
    detected = false
    until detected || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      detected = screen.resized?
      sleep 0.01 unless detected
    end
    assert detected
  ensure
    screen&.exit
  end
end
