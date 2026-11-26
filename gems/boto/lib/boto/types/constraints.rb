# frozen_string_literal: true

module Boto
  module Types
    # Restrictions checked after coercion. Options are validated and messages built once, in initialize.
    class Constraints
      Rule = Data.define(:keywords, :min_message, :max_message)

      RULES = {
        number: Rule.new(
          keywords: %w[minimum maximum].freeze,
          min_message: "must be greater than or equal to %s",
          max_message: "must be less than or equal to %s"
        ),
        characters: Rule.new(
          keywords: %w[minLength maxLength].freeze,
          min_message: "must have at least %s characters",
          max_message: "must have at most %s characters"
        ),
        items: Rule.new(
          keywords: %w[minItems maxItems].freeze,
          min_message: "must have at least %s items",
          max_message: "must have at most %s items"
        )
      }.freeze

      PATTERN_MESSAGE = "must match the pattern"
      ANCHOR_START = '\A'
      ANCHOR_END = '\z'
      JSON_ANCHOR_START = "^"
      JSON_ANCHOR_END = "$"

      def initialize(unit:, min: nil, max: nil, pattern: nil, enum: nil)
        @unit = unit
        @rule = RULES[unit]
        validate_bounds!(min, max)
        validate_pattern!(pattern)
        @min = min
        @max = max
        @min_message = min && format(@rule.min_message, min)
        @max_message = max && format(@rule.max_message, max)
        @pattern = pattern
        @enum = enum
        @json_keywords = build_json_keywords.freeze
        freeze
      end

      attr_reader :json_keywords

      def violation(value)
        bound_violation(value) || enum_violation(value) || pattern_violation(value)
      end

      private

      def validate_bounds!(min, max)
        return if min.nil? && max.nil?
        raise ArgumentError, "min and max are not supported for this type" if @rule.nil?
        return if [min, max].all? { |bound| bound.nil? || bound.is_a?(Numeric) }

        raise ArgumentError, "min and max must be Numeric"
      end

      def validate_pattern!(pattern)
        return if pattern.nil?
        raise ArgumentError, "pattern is only supported for String" unless @unit == :characters
        raise ArgumentError, "pattern must be a Regexp" unless pattern.is_a?(Regexp)
        return if anchored?(pattern.source)

        raise ArgumentError, "pattern must be anchored with \\A and \\z"
      end

      def anchored?(source)
        source.start_with?(ANCHOR_START) && source.end_with?(ANCHOR_END)
      end

      def bound_violation(value)
        return unless @min || @max

        size = measure(value)
        return @min_message if @min && size < @min

        @max_message if @max && size > @max
      end

      def enum_violation(value)
        return if @enum.nil? || @enum.values.include?(value)

        @enum.message
      end

      def pattern_violation(value)
        return if @pattern.nil? || @pattern.match?(value)

        PATTERN_MESSAGE
      end

      def measure(value)
        case @unit
        when :characters then value.length
        when :items then value.size
        else value
        end
      end

      def build_json_keywords
        keywords = {}
        keywords[@rule.keywords.first] = @min if @min
        keywords[@rule.keywords.last] = @max if @max
        keywords["pattern"] = json_pattern if @pattern
        keywords["enum"] = @enum.json if @enum
        keywords
      end

      def json_pattern
        body = @pattern.source.delete_prefix(ANCHOR_START).delete_suffix(ANCHOR_END)
        "#{JSON_ANCHOR_START}#{body}#{JSON_ANCHOR_END}".freeze
      end
    end
  end
end
