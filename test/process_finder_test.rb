# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

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

  def test_find_all_returns_pid_cwd_slug_and_cmdline_for_matching_processes
    Dir.mktmpdir do |root|
      fake_process(root, 100, comm: "claude", cwd: "/home/x/proj", cmdline: %w[claude --resume])
      fake_process(root, 200, comm: "other", cwd: "/home/x/other", cmdline: %w[other])

      found = Aiwatch::ProcessFinder.find_all(command_name: "claude", proc_root: root)
      assert_equal 1, found.length
      entry = found.first
      assert_equal 100, entry[:pid]
      assert_equal "/home/x/proj", entry[:cwd]
      assert_equal "-home-x-proj", entry[:slug]
      assert_equal %w[claude --resume], entry[:cmdline]
    end
  end

  def test_find_all_returns_empty_array_without_a_proc_directory
    assert_equal [], Aiwatch::ProcessFinder.find_all(proc_root: "/nonexistent-proc-root")
  end

  def test_find_pid_via_injected_proc_root
    Dir.mktmpdir do |root|
      fake_process(root, 100, comm: "claude", cwd: "/home/x/proj", cmdline: %w[claude])
      session_file = File.join(root, "-home-x-proj", "uuid.jsonl")
      assert_equal 100, Aiwatch::ProcessFinder.find_pid(session_file, command_name: "claude", proc_root: root)
    end
  end

  private

  # /proc/PID/cwd is a symlink whose target the kernel keeps current
  # regardless of what's actually at that path — File.readlink only ever
  # reads the link's target string, so the target doesn't need to exist.
  def fake_process(root, pid, comm:, cwd:, cmdline:)
    dir = File.join(root, pid.to_s)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "comm"), "#{comm}\n")
    File.write(File.join(dir, "cmdline"), cmdline.join("\0") + "\0")
    File.symlink(cwd, File.join(dir, "cwd"))
  end

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
