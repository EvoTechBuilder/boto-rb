# frozen_string_literal: true

require "optparse"

module Boto
  module CLI
    class Command
      SUCCESS = 0
      FAILURE = 1
      BOTOFILE_NAME = "Botofile"
      HELP_INDENT = "  "
      HELP_GAP = "   "
      OPTIONS = [].freeze

      # flags: names in display order, the last one is the long form the parser switch uses.
      # given: the value a switch without argument stores (e.g. false for --no-reload).
      Option = Data.define(:key, :flags, :description, :argument, :type, :given) do
        def initialize(key:, flags:, description:, argument: nil, type: nil, given: true)
          super
        end

        def label = [flags.join(", "), argument].compact.join(" ")

        def switches = [*flags[0...-1], [flags.last, argument].compact.join(" ")]
      end

      attr_reader :argv, :out, :err, :cwd

      def self.position = self::POSITION

      def self.options = self::OPTIONS

      # Returns the text without a trailing newline, so the caller decides how to print it.
      def self.help
        sections = [self::USAGE, self::SUMMARY]
        sections << options_help if options.any?
        sections.join("\n\n")
      end

      def self.options_help
        rows = options.map { |option| [option.label, option.description] }
        width = rows.map { |label, _| label.size }.max
        lines = rows.map { |label, text| "#{HELP_INDENT}#{label.ljust(width)}#{HELP_GAP}#{text}" }
        ["Options:", *lines].join("\n")
      end

      def initialize(argv, out:, err:, cwd:)
        @argv = argv
        @out = out
        @err = err
        @cwd = cwd
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private

      def solution
        path = File.join(cwd, BOTOFILE_NAME)
        raise Error, "Botofile not found in #{cwd}" unless File.file?(path)

        loaded = Botofile.load(path)
        Boto::Layout.check!(loaded, root: cwd)
        loaded
      end

      # Builds the parser from the command's OPTIONS, so the parser and the help cannot diverge.
      def option_parser(values)
        OptionParser.new do |parser|
          parser.banner = self.class::USAGE
          self.class.options.each { |option| add_option(parser, option, values) }
        end
      end

      def add_option(parser, option, values)
        args = [*option.switches, option.type].compact
        parser.on(*args) { |value| values[option.key] = option.argument ? value : option.given }
      end
    end
  end
end
