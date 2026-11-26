# frozen_string_literal: true

module Boto
  module OpenAPI
    # Every schema reachable from the roots, once each, keyed by schema_name.
    class SchemaCatalog
      def self.collect(roots)
        found = {}
        pending = roots.dup
        until pending.empty?
          schema = pending.shift
          existing = found[schema.schema_name]
          next if existing.equal?(schema)
          raise ArgumentError, "two different schemas are named #{schema.schema_name}" if existing

          found[schema.schema_name] = schema
          pending.concat(nested_schemas(schema))
        end
        found
      end

      # Schema#nested_schemas is private, so the fields are read here through the public API.
      def self.nested_schemas(schema)
        schema.fields.flat_map { |field| [field.declared_type].flatten }.select do |type|
          Types::SchemaRef.schema?(type)
        end
      end

      private_class_method :nested_schemas
    end
  end
end
