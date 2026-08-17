# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class GitBranchTest < Minitest::Test
  def test_returns_the_branch_name_for_a_normal_repo
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, ".git", "HEAD"), "ref: refs/heads/main\n")
      assert_equal "main", Aiwatch::GitBranch.for(dir)
    end
  end

  def test_walks_upward_to_find_the_repo_root
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, ".git", "HEAD"), "ref: refs/heads/feat/thing\n")
      sub = File.join(dir, "a", "b", "c")
      FileUtils.mkdir_p(sub)
      assert_equal "feat/thing", Aiwatch::GitBranch.for(sub)
    end
  end

  def test_detached_head_reports_a_short_sha
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, ".git", "HEAD"), "85c8e16b476be5b89cccb247b33e94c138457529\n")
      assert_equal "det:85c8e16", Aiwatch::GitBranch.for(dir)
    end
  end

  def test_worktree_gitdir_indirection_is_followed
    Dir.mktmpdir do |dir|
      main_git = File.join(dir, "main", ".git")
      FileUtils.mkdir_p(File.join(main_git, "worktrees", "feat-x"))
      File.write(File.join(main_git, "HEAD"), "ref: refs/heads/main\n")
      File.write(File.join(main_git, "worktrees", "feat-x", "HEAD"), "ref: refs/heads/feat-x\n")

      worktree_dir = File.join(dir, "worktree")
      FileUtils.mkdir_p(worktree_dir)
      File.write(File.join(worktree_dir, ".git"), "gitdir: #{File.join(main_git, "worktrees", "feat-x")}\n")

      assert_equal "feat-x", Aiwatch::GitBranch.for(worktree_dir)
    end
  end

  def test_relative_worktree_gitdir_path_is_resolved_against_the_gitfile_directory
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      FileUtils.mkdir_p(target)
      File.write(File.join(target, "HEAD"), "ref: refs/heads/relative-branch\n")

      worktree_dir = File.join(dir, "worktree")
      FileUtils.mkdir_p(worktree_dir)
      File.write(File.join(worktree_dir, ".git"), "gitdir: ../target\n")

      assert_equal "relative-branch", Aiwatch::GitBranch.for(worktree_dir)
    end
  end

  def test_returns_nil_when_not_a_git_repo
    Dir.mktmpdir do |dir|
      assert_nil Aiwatch::GitBranch.for(dir)
    end
  end

  def test_returns_nil_for_a_nonexistent_directory
    assert_nil Aiwatch::GitBranch.for("/nonexistent/definitely/not/here")
  end
end
