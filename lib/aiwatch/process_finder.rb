# frozen_string_literal: true

module Aiwatch
  # Finds the PID of the process that currently has a given file open, by
  # scanning /proc/*/fd — the only way to do this without an external
  # dependency (no lsof, no gem), which matters because this project has
  # zero runtime dependencies by design. Linux-only: /proc doesn't exist
  # on macOS, so this returns nil there rather than raising — `live`'s
  # kill action then just reports "process not found" instead of crashing.
  module ProcessFinder
    module_function

    def find_pid(file_path)
      return nil unless File.directory?("/proc")

      target = File.expand_path(file_path)
      Dir.foreach("/proc") do |pid|
        next unless /\A\d+\z/.match?(pid)

        fds = begin
          Dir.children("/proc/#{pid}/fd")
        rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
          next
        end

        fds.each do |fd|
          link = begin
            File.readlink("/proc/#{pid}/fd/#{fd}")
          rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
            next
          end
          return pid.to_i if link == target
        end
      end
      nil
    end
  end
end
