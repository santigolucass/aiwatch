# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TailReaderTest < Minitest::Test
  def with_file(content = "")
    Tempfile.create("aiwatch-tail") do |f|
      f.write(content)
      f.flush
      yield f.path
    end
  end

  def test_reads_all_lines_on_first_call_when_smaller_than_tail_bytes
    with_file("a\nb\nc\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      lines = reader.read_new_lines(File.stat(path))
      assert_equal %w[a b c], lines
    end
  end

  def test_returns_only_newly_appended_lines_on_a_later_call
    with_file("a\nb\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      reader.read_new_lines(File.stat(path))

      File.open(path, "a") { |f| f.write("c\nd\n") }
      lines = reader.read_new_lines(File.stat(path))
      assert_equal %w[c d], lines
    end
  end

  def test_buffers_a_trailing_partial_line_until_it_is_completed
    with_file("a\nb") do |path|
      reader = Aiwatch::TailReader.new(path)
      lines = reader.read_new_lines(File.stat(path))
      assert_equal %w[a], lines

      File.open(path, "a") { |f| f.write("c\n") }
      lines = reader.read_new_lines(File.stat(path))
      assert_equal %w[bc], lines
    end
  end

  def test_returns_empty_array_when_nothing_new
    with_file("a\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      reader.read_new_lines(File.stat(path))
      assert_equal [], reader.read_new_lines(File.stat(path))
    end
  end

  def test_tail_seeks_past_a_large_leading_portion_on_cold_start
    content = (0...100).map { |i| "line#{i}" }.join("\n") + "\n"
    with_file(content) do |path|
      reader = Aiwatch::TailReader.new(path)
      lines = reader.read_new_lines(File.stat(path), tail_bytes: 20)
      refute_includes lines, "line0"
      assert_equal "line99", lines.last
      assert reader.tail_seeked?
      assert_operator reader.first_read_offset, :>, 0
    end
  end

  def test_tail_seeked_is_a_one_shot_signal
    content = (0...100).map { |i| "line#{i}" }.join("\n") + "\n"
    with_file(content) do |path|
      reader = Aiwatch::TailReader.new(path)
      reader.read_new_lines(File.stat(path), tail_bytes: 20)
      assert reader.tail_seeked?

      File.open(path, "a") { |f| f.write("more\n") }
      reader.read_new_lines(File.stat(path), tail_bytes: 20)
      refute reader.tail_seeked?
    end
  end

  def test_does_not_tail_seek_when_file_is_smaller_than_tail_bytes
    with_file("a\nb\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      lines = reader.read_new_lines(File.stat(path), tail_bytes: 1_000_000)
      assert_equal %w[a b], lines
      refute reader.tail_seeked?
      assert_equal 0, reader.first_read_offset
    end
  end

  def test_detects_truncation_and_resets
    with_file("a\nb\nc\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      reader.read_new_lines(File.stat(path))

      File.write(path, "x\n")
      lines = reader.read_new_lines(File.stat(path))
      assert_equal %w[x], lines
      assert reader.reset?
    end
  end

  def test_detects_rotation_via_inode_change
    with_file("a\nb\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      reader.read_new_lines(File.stat(path))

      File.delete(path)
      File.write(path, "fresh\n")
      lines = reader.read_new_lines(File.stat(path))
      assert_equal %w[fresh], lines
      assert reader.reset?
    end
  end

  def test_reset_is_a_one_shot_signal
    with_file("a\n") do |path|
      reader = Aiwatch::TailReader.new(path)
      reader.read_new_lines(File.stat(path))
      refute reader.reset?

      File.open(path, "a") { |f| f.write("b\n") }
      reader.read_new_lines(File.stat(path))
      refute reader.reset?
    end
  end

  def test_returns_nil_when_the_file_does_not_exist
    reader = Aiwatch::TailReader.new("/nonexistent/path/does-not-exist.jsonl")
    fake_stat = Struct.new(:ino, :size).new(1, 0)
    assert_nil reader.read_new_lines(fake_stat)
  end
end
