# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"

class Boto::CLI::RunnerTest < Minitest::Test
  def setup
    @out = StringIO.new
    @err = StringIO.new
    @cwd = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@cwd)
  end

  def test_help_lists_commands_and_returns_zero
    %w[help -h --help].each do |flag|
      @out = StringIO.new
      assert_equal 0, runner.run([flag]), flag
      assert_match(/^  new  Create a new solution$/, @out.string)
    end
  end

  def test_no_arguments_shows_help
    assert_equal 0, runner.run([])
    assert_includes @out.string, "  new  Create a new solution"
  end

  def test_unknown_command_returns_one_with_message
    assert_equal 1, runner.run(["deploy"])
    assert_equal %(boto: unknown command "deploy"\n), @err.string
  end

  def test_malicious_or_non_existent_names_are_unknown
    ["../x", "New", "kernel", "Kernel", "new!"].each do |name|
      @err = StringIO.new
      assert_equal 1, runner.run([name]), name
      assert_equal %(boto: unknown command "#{name}"\n), @err.string
    end
  end

  def test_command_error_is_reported_as_usage
    assert_equal 1, runner.run(["new"])
    assert_equal "boto: usage: boto new <name>\n", @err.string
  end

  private

  def runner
    Boto::CLI::Runner.new(out: @out, err: @err, cwd: @cwd)
  end

  def test_isolation_error_is_reported_without_backtrace
    File.write(File.join(@cwd, "Botofile"), <<~BOTO)
      solution "shop"
      project "billing", template: :library
      project "orders", template: :webapi
    BOTO
    FileUtils.mkdir_p(File.join(@cwd, "services/orders/endpoints"))
    File.write(File.join(@cwd, "services/orders/endpoints/receipt.rb"), "Billing::Invoice\n")

    status = Boto::CLI::Runner.new(out: @out, err: @err, cwd: @cwd).run(%w[run --port 0])

    assert_equal 1, status
    assert_includes @err.string, "boto: project \"orders\" uses projects it does not reference"
    assert_includes @err.string, "Fix: boto ref orders billing"
  end
end
