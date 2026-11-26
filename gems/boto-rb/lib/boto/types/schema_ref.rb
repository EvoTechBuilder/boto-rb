# frozen_string_literal: true

module Boto
  module Types
    # Adapter for a schema class (duck typed: coerce, serialize, json_schema_ref).
    class SchemaRef
      SCHEMA_METHODS = %i[coerce serialize json_schema_ref].freeze

      attr_reader :json_schema

      def self.schema?(type)
        type.is_a?(Class) && SCHEMA_METHODS.all? { |name| type.respond_to?(name) }
      end

      def self.build(schema, min:, max:, enum:, pattern:)
        Types.reject_options!("schema types", min:, max:, enum:, pattern:)
        new(schema)
      end

      def initialize(schema)
        @schema = schema
        @json_schema = frozen_copy(schema.json_schema_ref)
        freeze
      end

      def coerce(value)
        @schema.coerce(value)
      end

      def dump(value)
        @schema.serialize(value)
      end

      private

      # Copies the schema's hash so the caller's object is not frozen as a side effect.
      def frozen_copy(value)
        case value
        when Hash then value.to_h { |key, item| [key, frozen_copy(item)] }.freeze
        when Array then value.map { |item| frozen_copy(item) }.freeze
        else value.dup.freeze
        end
      end
    end
  end
end
