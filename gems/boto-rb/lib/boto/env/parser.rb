# frozen_string_literal: true

module Boto
  class Env
    # Reads the .env subset from proposal 0020. Nothing is interpolated or executed.
    module Parser
      EXPORT_PREFIX = /\Aexport\s+/
      KEY_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
      DOUBLE_QUOTED = /\A"((?:[^"\\]|\\.)*)"(?:\s+#.*)?\z/
      SINGLE_QUOTED = /\A'([^']*)'(?:\s+#.*)?\z/
      INLINE_COMMENT = /\s+#.*\z/
      ESCAPE_SEQUENCE = /\\./
      ESCAPES = { "n" => "\n", "t" => "\t", '"' => '"', "\\" => "\\" }.freeze
      QUOTES = ['"', "'"].freeze

      def self.parse(text, path:)
        vars = {}
        text.each_line.with_index(1) do |line, number|
          entry = parse_line(line, path:, number:)
          vars[entry.first] = entry.last if entry
        end
        vars.freeze
      end

      def self.parse_line(line, path:, number:)
        body = line.strip
        return if body.empty? || body.start_with?("#")

        key, separator, raw_value = body.sub(EXPORT_PREFIX, "").partition("=")
        raise ParseError, "#{path}:#{number}: invalid line" if separator.empty?

        key = key.strip
        raise ParseError, %(#{path}:#{number}: invalid key "#{key}") unless KEY_PATTERN.match?(key)

        [key.freeze, parse_value(raw_value, path:, number:)]
      end

      def self.parse_value(raw_value, path:, number:)
        value = raw_value.strip
        return unquote(value) if quoted?(value)
        raise ParseError, "#{path}:#{number}: invalid line" if QUOTES.include?(value[0])

        raw_value.sub(INLINE_COMMENT, "").strip.freeze
      end

      def self.quoted?(value)
        DOUBLE_QUOTED.match?(value) || SINGLE_QUOTED.match?(value)
      end

      def self.unquote(value)
        if (match = DOUBLE_QUOTED.match(value))
          match[1].gsub(ESCAPE_SEQUENCE) { |sequence| ESCAPES.fetch(sequence[1]) { sequence } }.freeze
        else
          SINGLE_QUOTED.match(value)[1].freeze
        end
      end

      private_class_method :parse_line, :parse_value, :quoted?, :unquote
    end
  end
end
