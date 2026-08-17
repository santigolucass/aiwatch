# frozen_string_literal: true

module Aiwatch
  # Samples /proc for per-process CPU%, memory%, uptime, and state — no
  # root, no external dependency (no `ps`, no gem). Linux-only, like
  # ProcessFinder; callers on a platform without /proc get nil back for
  # everything rather than a crash.
  #
  # CPU% is fundamentally a two-sample measurement (Linux only exposes
  # cumulative CPU-tick counters, not an instantaneous rate) — verified
  # empirically against real running `claude` processes on this machine.
  # A pid's first #sample call returns cpu_percent: nil; only the SECOND
  # and later calls, once this object has a previous sample to diff
  # against, return a real number.
  class ProcStats
    Reading = Struct.new(:cpu_percent, :mem_percent, :uptime_seconds, :state, :threads)

    def initialize(proc_root: "/proc", clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @proc_root = proc_root
      @clock = clock
      @previous = {}
      @clk_tck = 100.0 # Linux's USER_HZ is 100 on every architecture aiwatch targets
    end

    def available?
      File.directory?(@proc_root)
    end

    # pids: Array of process ids (Integer or String). Returns
    # Hash[pid] => Reading for every pid whose /proc entry could be read;
    # a pid that's already gone by the time it's sampled is simply
    # absent from the result, not an error.
    def sample(pids)
      return {} unless available?

      now = @clock.call
      mem_total_kb = read_mem_total_kb
      uptime = read_uptime

      pids.each_with_object({}) do |pid, out|
        raw = read_stat(pid)
        next unless raw

        status = read_status(pid)
        reading = build_reading(pid, raw, status, mem_total_kb, uptime, now)
        out[pid.to_i] = reading if reading
      end
    end

    private

    def build_reading(pid, raw, status, mem_total_kb, uptime, now)
      cpu = cpu_percent(pid, raw, now)
      mem = (mem_total_kb&.positive? && status) ? (100.0 * status[:rss_kb] / mem_total_kb) : nil
      up = (uptime && raw[:starttime]) ? (uptime - (raw[:starttime] / @clk_tck)) : nil
      @previous[pid.to_i] = [raw, now]
      Reading.new(cpu, mem, up, raw[:state], status && status[:threads])
    end

    def cpu_percent(pid, raw, now)
      prev, prev_at = @previous[pid.to_i]
      return nil unless prev

      dt = now - prev_at
      return nil unless dt.positive?

      delta_ticks = (raw[:utime] + raw[:stime]) - (prev[:utime] + prev[:stime])
      return nil if delta_ticks.negative?

      100.0 * delta_ticks / (@clk_tck * dt)
    end

    # /proc/PID/stat's fields after the process name are space-separated,
    # but the name itself (in parens) can contain spaces or parens, so it
    # has to be located by the LAST ")" on the line, not split blindly.
    def read_stat(pid)
      raw = File.read(File.join(@proc_root, pid.to_s, "stat"))
      fields = raw[(raw.rindex(")") + 2)..].split
      {state: fields[0], utime: fields[11].to_i, stime: fields[12].to_i, starttime: fields[19].to_i}
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end

    def read_status(pid)
      text = File.read(File.join(@proc_root, pid.to_s, "status"))
      {rss_kb: text[/VmRSS:\s+(\d+)/, 1].to_i, threads: text[/Threads:\s+(\d+)/, 1].to_i}
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end

    def read_uptime
      File.read(File.join(@proc_root, "uptime")).split.first.to_f
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end

    def read_mem_total_kb
      text = File.read(File.join(@proc_root, "meminfo"))
      text[/MemTotal:\s+(\d+)/, 1].to_i
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end
  end
end
