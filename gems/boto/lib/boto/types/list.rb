# frozen_string_literal: true

module Boto
  module Types
    # A list of one item type. Item errors are prefixed with their index and aggregated.
    class List
      MUST_BE_ARRAY = "must be an array"

      attr_reader :json_schema

      def self.build(type, min:, max:, enum:, pattern:)
        Types.reject_options!("lists", enum:, pattern:)
        raise ArgumentError, "list type must have exactly one item type" unless type.size == 1

        new(Types.build(type.first), Constraints.new(unit: :items, min:, max:))
      end

      def initialize(item, constraints)
        @item = item
        @constraints = constraints
        @json_schema = { "type" => "array", "items" => item.json_schema }.merge(constraints.json_keywords).freeze
        freeze
      end

      def coerce(value)
        raise Invalid.single(MUST_BE_ARRAY) unless value.is_a?(Array)

        errors = []
        coerced = value.each_with_index.map { |item, index| coerce_item(item, index, errors) }
        raise Invalid.new(errors) if errors.any?

        message = @constraints.violation(coerced)
        raise Invalid.single(message) if message

        coerced
      end

      def dump(value)
        value.map { |item| @item.dump(item) }
      end

      private

      def coerce_item(item, index, errors)
        @item.coerce(item)
      rescue Invalid => e
        errors.concat(e.errors.map { |error| prefix_error(error, index) })
        nil
      end

      def prefix_error(error, index)
        error.merge(path: Types.join_path("[#{index}]", error[:path]))
      end
    end
  end
end
