# frozen_string_literal: true

module Boto
  module Types
    # Allowed values of a scalar type. Values are coerced once, at build time.
    class Enum
      attr_reader :values, :json, :message

      def initialize(options, definition)
        raise ArgumentError, "enum must be a non-empty Array" unless options.is_a?(Array) && !options.empty?

        @values = options.map { |option| coerce_option(option, definition) }.freeze
        @json = @values.map(&definition.dumper).freeze
        @message = "must be one of: #{@json.join(', ')}".freeze
        freeze
      end

      private

      def coerce_option(option, definition)
        coerced = definition.coercer.call(option)
        raise ArgumentError, "enum values must match the type" if coerced.nil?

        coerced
      end
    end
  end
end
