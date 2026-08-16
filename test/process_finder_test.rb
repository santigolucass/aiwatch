# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "rbconfig"

class ProcessFinderTest < Minitest::Test
  def test_finds_the_pid_of_a_process_with_the_file_open
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    with_holder_process do |pid, path|
      found = wait_until { Aiwatch::ProcessFinder.find_pid(path) }
      assert_equal pid, found
    end
  end

  def test_returns_nil_when_no_process_has_the_file_open
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "unused.jsonl")
      File.write(path, "")

      assert_nil Aiwatch::ProcessFinder.find_pid(path)
    end
  end

  private

  # Spawns a separate Ruby process that opens `path` and holds it open —
  # deliberately not opened by this test process itself, or find_pid could
  # match the test process's own fd instead of the child's.
  def with_holder_process
    Dir.mktmpdir do |dir|
      path = File.join(dir, "holder.jsonl")
      File.write(path, "")

      pid = Process.spawn(RbConfig.ruby, "-e", "File.open(ARGV[0]); sleep 5", path, out: File::NULL, err: File::NULL)
      begin
        yield pid, path
      ensure
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    result = nil
    loop do
      result = yield
      break if result || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.02
    end
    result
  end
end
