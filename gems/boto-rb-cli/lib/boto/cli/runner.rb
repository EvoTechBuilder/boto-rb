# frozen_string_literal: true

require "did_you_mean"

module Boto
  module CLI
    class Runner
      COMMAND_FORMAT = /\A[a-z]+\z/
      HELP_FLAGS = %w[-h --help].freeze
      VERSION_FLAGS = %w[-v --version version].freeze
      HELP_COMMAND = "help"
      TAGLINE = "Ruby framework for APIs and microservices organized as solutions"
      USAGE = "Usage: boto <command> [options]"
      COMMANDS_HEADER = "Commands:"
      OPTIONS_HEADER = "Options:"
      GLOBAL_OPTIONS = [
        ["-h, --help", "Show this help"],
        ["-v, --version", "Show the version"]
      ].freeze
      HELP_FOOTER = %(Run "boto help <command>" for the options of a command.)
      DOCS_LINE = "Docs: https://github.com/EvoTechBuilder/boto-rb"
      UNKNOWN_HINT = %(Run "boto --help" to see the commands.)
      COLUMN_GAP = "   "

      def initialize(out:, err:, cwd:)
        @out = out
        @err = err
        @cwd = cwd
      end

      def run(argv)
        name, *rest = argv
        return print_help if name.nil? || HELP_FLAGS.include?(name)
        return print_version if VERSION_FLAGS.include?(name)
        return run_help(rest.first) if name == HELP_COMMAND

        run_command(name, rest)
      rescue Error, Botofile::InvalidError, IsolationError, LegacyLayoutError => error
        @err.puts "boto: #{error.message}"
        Command::FAILURE
      end

      private

      def run_help(topic)
        return print_help if topic.nil? || HELP_FLAGS.include?(topic)

        run_command(topic, %w[--help])
      end

      # Help flags are checked before instantiating, so `boto new -h` never runs the command.
      def run_command(name, args)
        command_class = find_command(name)
        return report_unknown(name) unless command_class
        return print_command_help(command_class) if args.intersect?(HELP_FLAGS)

        command_class.new(args, out: @out, err: @err, cwd: @cwd).call
      end

      def print_help
        @out.puts(
          ["Boto #{Boto::CLI::VERSION} - #{TAGLINE}", "", USAGE, "", COMMANDS_HEADER,
           *table(command_rows), "", OPTIONS_HEADER, *table(GLOBAL_OPTIONS), "", HELP_FOOTER, DOCS_LINE]
        )
        Command::SUCCESS
      end

      def print_version
        @out.puts "boto #{Boto::CLI::VERSION} (ruby #{RUBY_VERSION})"
        Command::SUCCESS
      end

      def print_command_help(command_class)
        @out.puts command_class.help
        Command::SUCCESS
      end

      def command_rows
        command_classes.map { |command_class| [command_name(command_class), command_class::SUMMARY] }
      end

      # The label column is as wide as its longest label, followed by a fixed gap.
      def table(rows)
        width = rows.map { |label, _| label.size }.max
        rows.map { |label, text| "#{Command::HELP_INDENT}#{label.ljust(width)}#{COLUMN_GAP}#{text}" }
      end

      def command_classes
        Commands.constants.filter_map do |const|
          command_class = Commands.const_get(const, false)
          command_class if command?(command_class)
        end.sort_by(&:position)
      end

      def command_names = command_classes.map { |command_class| command_name(command_class) }

      def command_name(command_class) = command_class.name.split("::").last.downcase

      def find_command(name)
        return unless COMMAND_FORMAT.match?(name)

        const = name.capitalize
        return unless Commands.const_defined?(const, false)

        command_class = Commands.const_get(const, false)
        command_class if command?(command_class)
      end

      # Only Command subclasses are runnable, so stray constants never become commands.
      def command?(value)
        value.is_a?(Class) && value < Command
      end

      def report_unknown(name)
        @err.puts unknown_message(name)
        @err.puts UNKNOWN_HINT
        Command::FAILURE
      end

      def unknown_message(name)
        message = %(boto: unknown command "#{name}")
        suggestion = DidYouMean::SpellChecker.new(dictionary: command_names).correct(name).first
        suggestion ? %(#{message}. Did you mean "#{suggestion}"?) : "#{message}."
      end
    end
  end
end
