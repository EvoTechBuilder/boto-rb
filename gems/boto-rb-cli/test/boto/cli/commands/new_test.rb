# frozen_string_literal: true

require "test_helper"
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

  private

  def new_command(argv, cwd:, out: StringIO.new)
    Boto::CLI::Commands::New.new(argv, out: out, err: StringIO.new, cwd: cwd)
  end
end
