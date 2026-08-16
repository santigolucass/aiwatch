# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ProcessFinderTest < Minitest::Test
  def test_finds_a_process_by_cwd_and_command_name
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    with_process(command: %w[sleep 5]) do |pid, dir|
      found = wait_until { Aiwatch::ProcessFinder.find_pid(dir, command_name: "sleep") }
      assert_equal pid, found
    end
  end

  def test_returns_nil_when_the_command_name_does_not_match_even_if_cwd_does
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    with_process(command: %w[sleep 5]) do |_pid, dir|
      wait_until { Aiwatch::ProcessFinder.find_pid(dir, command_name: "sleep") } # ensure it's registered
      assert_nil Aiwatch::ProcessFinder.find_pid(dir, command_name: "claude")
    end
  end

  def test_returns_nil_when_no_process_has_that_cwd
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    Dir.mktmpdir do |dir|
      assert_nil Aiwatch::ProcessFinder.find_pid(dir, command_name: "sleep")
    end
  end

  def test_returns_nil_when_more_than_one_process_matches_rather_than_guessing
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    Dir.mktmpdir do |dir|
      pid1 = Process.spawn("sleep", "5", chdir: dir, out: File::NULL, err: File::NULL)
      pid2 = Process.spawn("sleep", "5", chdir: dir, out: File::NULL, err: File::NULL)
      begin
        wait_until { Aiwatch::ProcessFinder.find_pid(dir, command_name: "sleep") } # ensure both registered
        assert_nil Aiwatch::ProcessFinder.find_pid(dir, command_name: "sleep")
      ensure
        [pid1, pid2].each { |pid| kill_and_wait(pid) }
      end
    end
  end

  private

  def with_process(command:)
    Dir.mktmpdir do |dir|
      pid = Process.spawn(*command, chdir: dir, out: File::NULL, err: File::NULL)
      begin
        yield pid, dir
      ensure
        kill_and_wait(pid)
      end
    end
  end

  def kill_and_wait(pid)
    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
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
