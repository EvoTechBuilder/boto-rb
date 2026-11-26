# frozen_string_literal: true

module Boto
  module CLI
    class Runner
      COMMAND_FORMAT = /\A[a-z]+\z/
      HELP_FLAGS = %w[help -h --help].freeze
      USAGE = "usage: boto <command> [args]"

      def initialize(out:, err:, cwd:)
        @out = out
        @err = err
        @cwd = cwd
      end

      def run(argv)
        name, *rest = argv
        return print_help if name.nil? || HELP_FLAGS.include?(name)

        command_class = find_command(name)
        return report_unknown(name) unless command_class

        command_class.new(rest, out: @out, err: @err, cwd: @cwd).call
      rescue Error, Botofile::InvalidError => error
        @err.puts "boto: #{error.message}"
        Command::FAILURE
      end

      private

      def print_help
        @out.puts USAGE
        @out.puts
        @out.puts "Commands:"
        command_entries.each { |name, command_class| @out.puts "  #{name}  #{command_class::SUMMARY}" }
        Command::SUCCESS
      end

      def command_entries
        Commands.constants.sort.filter_map do |const|
          command_class = Commands.const_get(const, false)
          [const.to_s.downcase, command_class] if command?(command_class)
        end
      end

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
        @err.puts %(boto: unknown command "#{name}")
        Command::FAILURE
      end
    end
  end
end
