# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::NewCommandTest < Minitest::Test
  def test_creates_loadable_solution
    Dir.mktmpdir do |cwd|
      out = StringIO.new
      assert_equal 0, new_command(["shop"], out: out, cwd: cwd).call

      solution = Boto::Botofile.load(File.join(cwd, "shop", "Botofile"))
      assert_equal "shop", solution.name
      assert_includes out.string, "create shop/Botofile"
      assert_includes out.string, "Next: cd shop && boto add webapi api"
    end
  end

  def test_creates_only_root_files
    Dir.mktmpdir do |cwd|
      new_command(["shop"], cwd: cwd).call

      assert_equal %w[.gitignore .ruby-version Botofile Gemfile], Dir.children(File.join(cwd, "shop")).sort
    end
  end

  def test_generates_gemfile_with_boto_security
    Dir.mktmpdir do |cwd|
      new_command(["shop"], cwd: cwd).call

      assert_includes File.read(File.join(cwd, "shop", "Gemfile")), %(gem "boto-rb-security")
    end
  end

  def test_generated_gemfile_includes_minitest_for_project_tests
    Dir.mktmpdir do |cwd|
      new_command(["shop"], cwd: cwd).call

      assert_includes File.read(File.join(cwd, "shop", "Gemfile")), %(gem "minitest")
    end
  end

  def test_existing_directory_raises
    Dir.mktmpdir do |cwd|
      Dir.mkdir(File.join(cwd, "shop"))
      error = assert_raises(Boto::CLI::Error) { new_command(["shop"], cwd: cwd).call }
      assert_equal %(directory "shop" already exists), error.message
    end
  end

  def test_invalid_name_raises
    Dir.mktmpdir do |cwd|
      ["Shop", "../x", "1shop", ""].each do |name|
        error = assert_raises(Boto::CLI::Error) { new_command([name], cwd: cwd).call }
        assert_equal %(invalid solution name "#{name}"), error.message
      end
    end
  end

  def test_missing_name_raises_usage
    Dir.mktmpdir do |cwd|
      error = assert_raises(Boto::CLI::Error) { new_command([], cwd: cwd).call }
      assert_equal "Usage: boto new <name>", error.message
    end
  end

  def test_gitignore_lists_env_files_but_not_the_example
    Dir.mktmpdir do |cwd|
      new_command(["shop"], cwd: cwd).call

      gitignore = File.read(File.join(cwd, "shop", ".gitignore"))
      assert_includes gitignore.lines.map(&:chomp), ".env.*"
      assert_includes gitignore.lines.map(&:chomp), "!.env.example"
    end
  end

  def test_git_ignores_env_files_in_subfolders_and_keeps_the_example
    skip "git is not installed" unless system("git", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |cwd|
      new_command(["shop"], cwd: cwd).call
      repo = File.join(cwd, "shop")
      system("git", "init", "-q", repo, out: File::NULL, err: File::NULL)
      touch_all(repo, %w[.env .env.local .env.development apps/x/.env.test.local .env.example])

      assert_equal %w[.env .env.local .env.development apps/x/.env.test.local],
                   ignored_paths(repo, %w[.env .env.local .env.development apps/x/.env.test.local .env.example])
    end
  end

  private

  def touch_all(repo, relatives)
    relatives.each do |relative|
      path = File.join(repo, relative)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
    end
  end

  # git check-ignore -q exits 0 for each ignored path; the paths are listed in the order given.
  def ignored_paths(repo, relatives)
    relatives.select do |relative|
      system("git", "-C", repo, "check-ignore", "-q", relative, out: File::NULL, err: File::NULL)
    end
  end

  def new_command(argv, cwd:, out: StringIO.new)
    Boto::CLI::Commands::New.new(argv, out: out, err: StringIO.new, cwd: cwd)
  end
end
