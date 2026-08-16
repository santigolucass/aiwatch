# frozen_string_literal: true

module Aiwatch
  # Finds the PID of a `command_name` process whose current working
  # directory matches a session's project — without an external
  # dependency (no lsof, no gem), which matters because this project has
  # zero runtime dependencies by design.
  #
  # This does NOT match by open file descriptor. Claude Code writes its
  # session log append-only — open, write, close — for each event rather
  # than holding the file open, so scanning /proc/*/fd almost never
  # catches it mid-write (verified against real running `claude`
  # processes: none had their .jsonl open at any given instant).
  # /proc/PID/cwd, by contrast, is maintained continuously by the kernel
  # regardless of what files are open, and a session's project already
  # *is* the cwd Claude Code recorded for it — so matching on that is both
  # more reliable and simpler.
  #
  # Linux-only: /proc doesn't exist on macOS, so this returns nil there
  # rather than raising. Returns nil (not a guess) when zero or more than
  # one process matches — sending a signal to the wrong process is worse
  # than not finding one.
  module ProcessFinder
    COMMAND_NAME = "claude"

    module_function

    def find_pid(cwd, command_name: COMMAND_NAME)
      return nil unless File.directory?("/proc")

      target = begin
        File.realpath(cwd)
      rescue Errno::ENOENT
        File.expand_path(cwd)
      end

      matches = Dir.foreach("/proc").select { |entry| /\A\d+\z/.match?(entry) }.select do |pid|
        safe_readlink("/proc/#{pid}/cwd") == target && safe_read("/proc/#{pid}/comm")&.strip == command_name
      end

      (matches.length == 1) ? matches.first.to_i : nil
    end

    def safe_readlink(path)
      File.readlink(path)
    rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
      nil
    end
    private_class_method :safe_readlink

    def safe_read(path)
      File.read(path)
    rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
      nil
    end
    private_class_method :safe_read
  end
end
