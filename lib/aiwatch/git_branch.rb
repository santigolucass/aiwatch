# frozen_string_literal: true

module Aiwatch
  # Reads the current git branch straight from a directory's .git, rather
  # than trusting the `gitBranch` field Claude Code logs on each JSONL
  # line — verified against real session files to be unreliable: it's
  # pinned to whatever directory the session originally launched from,
  # and reports the literal string "HEAD" whenever THAT directory isn't a
  # git repo, even while the session's actual cwd later moved into one
  # (see docs/decisions.md). Reading .git/HEAD directly from a live
  # process's real, current cwd (via ProcessFinder) is unaffected by any
  # of that, and reading it repeatedly is effectively free — measured at
  # ~1ms per read, page-cached, on a real machine.
  module GitBranch
    module_function

    # dir: an absolute path, normally a live process's current cwd.
    # Returns the branch name, "det:<7-char-sha>" for a detached HEAD, or
    # nil if `dir` isn't inside a git working tree at all.
    def for(dir)
      git_dir = locate_git_dir(dir)
      return nil unless git_dir

      head = read_head(git_dir)
      return nil unless head

      parse_head(head)
    end

    # Walks upward from `dir` looking for a `.git` entry, the same way
    # git itself resolves a working tree. `.git` is a directory for a
    # normal repo, or a file containing "gitdir: <path>" for a worktree
    # — followed here so worktrees report their own branch, not the main
    # checkout's.
    def locate_git_dir(dir)
      current = File.expand_path(dir)
      loop do
        candidate = File.join(current, ".git")
        if File.directory?(candidate)
          return candidate
        elsif File.file?(candidate)
          resolved = resolve_worktree_gitdir(candidate)
          return resolved if resolved
        end

        parent = File.dirname(current)
        return nil if parent == current

        current = parent
      end
    end
    private_class_method :locate_git_dir

    def resolve_worktree_gitdir(gitfile_path)
      content = File.read(gitfile_path)
      match = content[/\Agitdir:\s*(.+)\s*\z/, 1]
      return nil unless match

      File.absolute_path?(match) ? match : File.expand_path(match, File.dirname(gitfile_path))
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end
    private_class_method :resolve_worktree_gitdir

    def read_head(git_dir)
      File.read(File.join(git_dir, "HEAD")).strip
    rescue Errno::ENOENT, Errno::EACCES, IOError
      nil
    end
    private_class_method :read_head

    def parse_head(head)
      ref = head[/\Aref:\s*refs\/heads\/(.+)\z/, 1]
      return ref if ref

      head.match?(/\A[0-9a-f]{7,40}\z/) ? "det:#{head[0, 7]}" : nil
    end
    private_class_method :parse_head
  end
end
