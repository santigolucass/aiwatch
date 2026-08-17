# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class ProcStatsTest < Minitest::Test
  # Builds a fake /proc/<pid>/{stat,status} pair plus /proc/{uptime,meminfo},
  # matching the real kernel's format closely enough for ProcStats to parse.
  def fake_proc(root, pid, utime:, stime:, starttime:, rss_kb: 500_000, state: "S", threads: 10)
    dir = File.join(root, pid.to_s)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "stat"), "#{pid} (claude) #{state} 1 #{pid} 1 0 -1 0 0 0 0 0 #{utime} #{stime} 0 0 20 0 #{threads} 0 #{starttime} 0 0")
    File.write(File.join(dir, "status"), "VmRSS:\t#{rss_kb} kB\nThreads:\t#{threads}\n")
  end

  def fake_system_files(root, uptime_seconds:, mem_total_kb:)
    File.write(File.join(root, "uptime"), "#{uptime_seconds} 0")
    File.write(File.join(root, "meminfo"), "MemTotal:       #{mem_total_kb} kB\n")
  end

  def test_unavailable_without_a_proc_directory
    stats = Aiwatch::ProcStats.new(proc_root: "/nonexistent-proc-root")
    refute stats.available?
    assert_equal({}, stats.sample([1]))
  end

  def test_first_sample_has_no_cpu_percent
    Dir.mktmpdir do |root|
      fake_proc(root, 100, utime: 1000, stime: 500, starttime: 0)
      fake_system_files(root, uptime_seconds: 1000, mem_total_kb: 1_000_000)
      stats = Aiwatch::ProcStats.new(proc_root: root)
      reading = stats.sample([100])[100]
      assert_nil reading.cpu_percent
    end
  end

  def test_second_sample_computes_cpu_percent_from_the_tick_delta
    Dir.mktmpdir do |root|
      fake_system_files(root, uptime_seconds: 1000, mem_total_kb: 1_000_000)
      t = 0.0
      stats = Aiwatch::ProcStats.new(proc_root: root, clock: -> { t })

      fake_proc(root, 100, utime: 1000, stime: 500, starttime: 0)
      stats.sample([100])

      t = 2.0 # 2 real seconds elapse
      fake_proc(root, 100, utime: 1100, stime: 500, starttime: 0) # +100 ticks of utime
      reading = stats.sample([100])[100]
      # 100 ticks / (100 ticks/sec * 2s) = 50%
      assert_in_delta 50.0, reading.cpu_percent, 0.01
    end
  end

  def test_mem_percent_from_rss_and_mem_total
    Dir.mktmpdir do |root|
      fake_proc(root, 100, utime: 0, stime: 0, starttime: 0, rss_kb: 250_000)
      fake_system_files(root, uptime_seconds: 100, mem_total_kb: 1_000_000)
      stats = Aiwatch::ProcStats.new(proc_root: root)
      reading = stats.sample([100])[100]
      assert_in_delta 25.0, reading.mem_percent
    end
  end

  def test_uptime_seconds_from_starttime_and_system_uptime
    Dir.mktmpdir do |root|
      fake_proc(root, 100, utime: 0, stime: 0, starttime: 500) # 500 ticks = 5s after boot
      fake_system_files(root, uptime_seconds: 100, mem_total_kb: 1_000_000)
      stats = Aiwatch::ProcStats.new(proc_root: root)
      reading = stats.sample([100])[100]
      assert_in_delta 95.0, reading.uptime_seconds
    end
  end

  def test_state_and_thread_count_are_read
    Dir.mktmpdir do |root|
      fake_proc(root, 100, utime: 0, stime: 0, starttime: 0, state: "R", threads: 7)
      fake_system_files(root, uptime_seconds: 100, mem_total_kb: 1_000_000)
      stats = Aiwatch::ProcStats.new(proc_root: root)
      reading = stats.sample([100])[100]
      assert_equal "R", reading.state
      assert_equal 7, reading.threads
    end
  end

  def test_gone_pid_is_absent_from_the_result_not_an_error
    Dir.mktmpdir do |root|
      fake_system_files(root, uptime_seconds: 100, mem_total_kb: 1_000_000)
      stats = Aiwatch::ProcStats.new(proc_root: root)
      result = stats.sample([999])
      assert_equal({}, result)
    end
  end

  def test_a_process_name_containing_parens_does_not_break_field_parsing
    Dir.mktmpdir do |root|
      dir = File.join(root, "100")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "stat"), "100 (weird (name)) S 1 100 1 0 -1 0 0 0 0 0 10 5 0 0 20 0 1 0 0 0 0")
      File.write(File.join(dir, "status"), "VmRSS:\t1000 kB\nThreads:\t1\n")
      fake_system_files(root, uptime_seconds: 100, mem_total_kb: 1_000_000)
      stats = Aiwatch::ProcStats.new(proc_root: root)
      reading = stats.sample([100])[100]
      assert_equal "S", reading.state
    end
  end
end
