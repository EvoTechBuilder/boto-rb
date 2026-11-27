# frozen_string_literal: true

require "test_helper"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::CommandTest < Minitest::Test
  COMMANDS = Boto::CLI::Commands.constants
                                .map { |name| Boto::CLI::Commands.const_get(name) }
                                .select { |klass| klass.is_a?(Class) && klass < Boto::CLI::Command }
                                .freeze

  def test_every_command_declares_summary_and_usage
    COMMANDS.each do |command|
      refute_empty command::SUMMARY, "#{command} needs a SUMMARY"
      assert command::USAGE.start_with?("Usage: boto #{command_name(command)}"), "#{command} USAGE"
    end
  end

  def test_every_command_declares_an_integer_position
    COMMANDS.each { |command| assert_kind_of Integer, command.position, "#{command} needs a POSITION" }
  end

  def test_positions_are_unique
    positions = COMMANDS.map(&:position)

    assert_equal positions.size, positions.uniq.size
  end

  def test_commands_without_options_have_an_empty_list
    assert_empty Boto::CLI::Commands::Ref.options
    assert_empty Boto::CLI::Command.options
  end

  def test_run_help_describes_its_options
    expected = <<~HELP.chomp
      Usage: boto run [project] [--port N] [--host H]

      Run the solution's services in one process

      Options:
        --port N               First port; each service gets the next one (default 3000)
        --host H               Host to bind (default 127.0.0.1)
        --shutdown-timeout N   Seconds to wait for requests in flight on shutdown (default 25)
        --drain-delay N        Seconds to keep serving after readiness turns 503 (default 0)
        --no-reload            Do not reload code changes (reload is on in development)
    HELP

    assert_equal expected, Boto::CLI::Commands::Run.help
  end

  def test_help_without_options_has_no_options_section
    expected = "Usage: boto ref <project> <reference>\n\nAdd a reference between projects"

    assert_equal expected, Boto::CLI::Commands::Ref.help
  end

  def test_help_has_no_trailing_newline
    refute Boto::CLI::Commands::Run.help.end_with?("\n")
  end

  private

  def command_name(command)
    command.name.split("::").last.downcase
  end
end
