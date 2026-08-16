# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ProcessFinderTest < Minitest::Test
  def test_finds_a_process_launched_from_the_sessions_project_directory
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    with_project(command: %w[sleep 5]) do |pid, session_file|
      found = wait_until { Aiwatch::ProcessFinder.find_pid(session_file, command_name: "sleep") }
      assert_equal pid, found
    end
  end

  def test_returns_nil_when_the_command_name_does_not_match_even_if_the_directory_does
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    with_project(command: %w[sleep 5]) do |_pid, session_file|
      wait_until { Aiwatch::ProcessFinder.find_pid(session_file, command_name: "sleep") } # ensure registered
      assert_nil Aiwatch::ProcessFinder.find_pid(session_file, command_name: "claude")
    end
  end

  def test_returns_nil_when_no_process_matches
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    Dir.mktmpdir do |base|
      session_file = build_session_file(base, "/tmp/nowhere-any-process-actually-runs")
      assert_nil Aiwatch::ProcessFinder.find_pid(session_file, command_name: "sleep")
    end
  end

  def test_returns_nil_when_more_than_one_process_matches_rather_than_guessing
    skip "requires /proc (Linux only)" unless File.directory?("/proc")

    Dir.mktmpdir do |base|
      launch_dir = File.join(base, "project-root")
      Dir.mkdir(launch_dir)
      session_file = build_session_file(base, launch_dir)

      pid1 = Process.spawn("sleep", "5", chdir: launch_dir, out: File::NULL, err: File::NULL)
      pid2 = Process.spawn("sleep", "5", chdir: launch_dir, out: File::NULL, err: File::NULL)
      begin
        wait_until { Aiwatch::ProcessFinder.find_pid(session_file, command_name: "sleep") } # ensure both registered
        assert_nil Aiwatch::ProcessFinder.find_pid(session_file, command_name: "sleep")
      ensure
        [pid1, pid2].each { |pid| kill_and_wait(pid) }
      end
    end
  end

  def test_slugify_matches_claude_codes_own_scheme
    assert_equal "-home-dev-code-myapp", Aiwatch::ProcessFinder.slugify("/home/dev/code/myapp")
    assert_equal "-home-dev-code-myapp--claude-worktrees-feat-x",
      Aiwatch::ProcessFinder.slugify("/home/dev/code/myapp/.claude/worktrees/feat-x")
  end

  private

  # Spawns `command` with its cwd set to a fresh launch directory, and
  # builds a fake session file living under a project directory slugified
  # from that same launch directory — mirroring how a real
  # ~/.claude/projects/<slug>/<uuid>.jsonl is laid out.
  def with_project(command:)
    Dir.mktmpdir do |base|
      launch_dir = File.join(base, "project-root")
      Dir.mkdir(launch_dir)
      session_file = build_session_file(base, launch_dir)

      pid = Process.spawn(*command, chdir: launch_dir, out: File::NULL, err: File::NULL)
      begin
        yield pid, session_file
      ensure
        kill_and_wait(pid)
      end
    end
  end

  def build_session_file(base, launch_dir)
    slug = Aiwatch::ProcessFinder.slugify(launch_dir)
    projects_dir = File.join(base, slug)
    Dir.mkdir(projects_dir)
    session_file = File.join(projects_dir, "11111111-2222-3333-4444-555555555555.jsonl")
    File.write(session_file, "")
    session_file
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
