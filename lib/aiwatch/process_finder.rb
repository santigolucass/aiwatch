# frozen_string_literal: true

module Aiwatch
  # Finds `command_name` processes by their real, current working
  # directory — without an external dependency (no lsof, no gem), which
  # matters because this project has zero runtime dependencies by
  # design.
  #
  # Does NOT match by open file descriptor (Claude Code writes its
  # session log append-only — open, write, close — per event, so
  # scanning /proc/*/fd almost never catches it mid-write), and does NOT
  # match directly against `Session#project` either: that's the most
  # *frequent* cwd across the session's events, which drifts to wherever
  # the agent's tool calls happened — a subdirectory, a git worktree —
  # and is very often NOT the real OS process's actual cwd, which stays
  # fixed at wherever `claude` was launched.
  #
  # What stays fixed and reliable instead: a session's log file lives
  # under ~/.claude/projects/<slug>/, and that slug is derived from the
  # launch directory once, at session start — it doesn't move just
  # because the agent `cd`s around during tool calls. So this matches a
  # candidate process by slugifying *its* real cwd (/proc/PID/cwd, which
  # the kernel keeps current regardless of open files) the same way
  # Claude Code names project directories, and comparing that against the
  # session file's actual parent directory name on disk.
  #
  # Linux-only: /proc doesn't exist on macOS, so this returns nil/empty
  # there rather than raising.
  module ProcessFinder
    COMMAND_NAME = "claude"
    DEFAULT_PROC_ROOT = "/proc"

    module_function

    # Every `command_name` process currently running, one /proc scan for
    # the whole dashboard (the live table's per-tick PID/BRANCH/CPU/MEM
    # columns all key off this) rather than one scan per session, which
    # is what repeatedly calling #find_pid would cost.
    def find_all(command_name: COMMAND_NAME, proc_root: DEFAULT_PROC_ROOT)
      return [] unless File.directory?(proc_root)

      Dir.foreach(proc_root).select { |entry| /\A\d+\z/.match?(entry) }.filter_map do |pid|
        next unless safe_read(File.join(proc_root, pid, "comm"))&.strip == command_name

        cwd = safe_readlink(File.join(proc_root, pid, "cwd"))
        next unless cwd

        cmdline = safe_read(File.join(proc_root, pid, "cmdline")).to_s.split("\0")
        {pid: pid.to_i, cwd: cwd, slug: slugify(cwd), cmdline: cmdline}
      end
    end

    # Returns nil (not a guess) when zero or more than one process
    # matches — sending a signal to the wrong process is worse than not
    # finding one.
    def find_pid(session_file_path, command_name: COMMAND_NAME, proc_root: DEFAULT_PROC_ROOT)
      target_slug = File.basename(File.dirname(File.expand_path(session_file_path)))
      matches = find_all(command_name: command_name, proc_root: proc_root).select { |p| p[:slug] == target_slug }
      (matches.length == 1) ? matches.first[:pid] : nil
    end

    def slugify(path)
      path.gsub(%r{[/.]}, "-")
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
