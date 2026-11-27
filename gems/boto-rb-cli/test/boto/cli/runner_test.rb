# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"

class Boto::CLI::RunnerTest < Minitest::Test
  COMMAND_ORDER = %w[new add ref graph check run test openapi].freeze

  def setup
    @out = StringIO.new
    @err = StringIO.new
    @cwd = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@cwd)
  end

  def test_general_help_lists_commands_in_flow_order_and_returns_zero
    %w[-h --help help].each do |flag|
      @out = StringIO.new
      assert_equal 0, runner.run([flag]), flag
      assert_general_help(@out.string)
    end
  end

  def test_no_arguments_shows_general_help
    assert_equal 0, runner.run([])
    assert_general_help(@out.string)
  end

  def test_general_help_starts_with_version_and_tagline
    runner.run([])

    assert_equal "Boto #{Boto::CLI::VERSION} - Ruby framework for APIs and microservices organized as solutions\n",
                 @out.string.lines.first
  end

  def test_version_flags_print_version_and_return_zero
    %w[-v --version version].each do |flag|
      @out = StringIO.new
      assert_equal 0, runner.run([flag]), flag
      assert_equal "boto #{Boto::CLI::VERSION} (ruby #{RUBY_VERSION})\n", @out.string
    end
  end

  def test_help_command_prints_command_help
    assert_equal 0, runner.run(%w[help run])
    assert_equal "#{Boto::CLI::Commands::Run.help}\n", @out.string
  end

  def test_command_help_flags_print_the_same_help
    %w[-h --help].each do |flag|
      @out = StringIO.new
      assert_equal 0, runner.run(["run", flag]), flag
      assert_equal "#{Boto::CLI::Commands::Run.help}\n", @out.string
    end
  end

  def test_command_help_flag_in_any_position_does_not_run_the_command
    assert_equal 0, runner.run(["new", "-h"])
    assert_equal 0, runner.run(["openapi", "orders", "--help"])
    assert_equal "#{Boto::CLI::Commands::New.help}\n#{Boto::CLI::Commands::Openapi.help}\n", @out.string
    assert_empty Dir.children(@cwd)
  end

  def test_unknown_command_suggests_the_closest_one
    assert_equal 1, runner.run(["chek"])
    assert_equal <<~ERR, @err.string
      boto: unknown command "chek". Did you mean "check"?
      Run "boto --help" to see the commands.
    ERR
  end

  def test_unknown_command_without_suggestion_returns_one
    assert_equal 1, runner.run(["xyzzy"])
    assert_equal <<~ERR, @err.string
      boto: unknown command "xyzzy".
      Run "boto --help" to see the commands.
    ERR
  end

  def test_help_with_unknown_command_suggests_the_closest_one
    assert_equal 1, runner.run(%w[help chek])
    assert_equal <<~ERR, @err.string
      boto: unknown command "chek". Did you mean "check"?
      Run "boto --help" to see the commands.
    ERR
  end

  def test_malicious_or_non_existent_names_are_unknown
    ["../x", "kernel", "Kernel", "new!"].each do |name|
      @err = StringIO.new
      assert_equal 1, runner.run([name]), name
      assert_includes @err.string, %(boto: unknown command "#{name}"), name
    end
  end

  def test_command_error_is_reported_as_usage
    assert_equal 1, runner.run(["new"])
    assert_equal "boto: Usage: boto new <name>\n", @err.string
  end

  def test_isolation_error_is_reported_without_backtrace
    File.write(File.join(@cwd, "Botofile"), <<~BOTO)
      solution "shop"
      project "billing", template: :library
      project "orders", template: :webapi
    BOTO
    FileUtils.mkdir_p(File.join(@cwd, "apps/orders/endpoints"))
    File.write(File.join(@cwd, "apps/orders/endpoints/receipt.rb"), "Billing::Invoice\n")

    status = runner.run(%w[run])

    assert_equal 1, status
    assert_includes @err.string, "boto: project \"orders\" uses projects it does not reference"
    assert_includes @err.string, "Fix: boto ref orders billing"
  end

  private

  def runner
    Boto::CLI::Runner.new(out: @out, err: @err, cwd: @cwd)
  end

  def assert_general_help(text)
    lines = text.lines.map(&:chomp)
    assert_includes lines, "Usage: boto <command> [options]"
    assert_includes lines, "  -h, --help      Show this help"
    assert_includes lines, "  -v, --version   Show the version"
    assert_includes lines, %(Run "boto help <command>" for the options of a command.)
    assert_equal COMMAND_ORDER, command_lines(lines).map { |line| line[/\A  (\S+)/, 1] }
    assert_one_column(command_lines(lines))
  end

  def command_lines(lines)
    after_header = lines.drop(lines.index("Commands:") + 1)
    after_header.take_while { |line| !line.empty? }
  end

  def assert_one_column(lines)
    # The label never contains spaces, so the description starts right after the first run of spaces.
    columns = lines.map { |line| line[/\A  \S+\s+/].size }
    assert_equal 1, columns.uniq.size, lines.join("\n")
  end
end
