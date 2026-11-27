# frozen_string_literal: true

module Boto
  module CLI
    # Parses "name:type" (a trailing "?" makes it optional) and renders the matching schema field line.
    # schema_reference is the schema file a non-scalar type points to, e.g. "category_schema", or nil.
    class FieldSpec < Data.define(:name, :type_source, :required, :schema_reference)
      IDENTIFIER = /\A[a-z][a-z0-9_]*\z/
      LIST = /\A\[(.+)\]\z/
      SCHEMA_SUFFIX = "schema"
      TYPES = {
        "string" => "String",
        "integer" => "Integer",
        "float" => "Float",
        "boolean" => "Boto::Boolean",
        "date" => "Date",
        "time" => "Time"
      }.freeze

      def self.parse(spec, namespace:)
        # The "?" is read from the whole spec, so it is stripped before splitting "name:type".
        parts = spec.delete_suffix("?").split(":", -1)
        raise invalid(spec) unless parts.size == 2

        name, type = parts
        raise invalid(spec) unless IDENTIFIER.match?(name)

        new(name:, type_source: type_source(type, namespace, spec), required: !spec.end_with?("?"),
            schema_reference: schema_reference(type, namespace))
      end

      def self.type_source(type, namespace, spec)
        element = element_source(element_type(type), namespace, spec)
        LIST.match?(type) ? "[#{element}]" : element
      end

      def self.element_source(type, namespace, spec)
        return TYPES[type] if TYPES.key?(type)
        raise invalid(spec) unless IDENTIFIER.match?(type)

        # A name already ending in "schema" is not suffixed twice (product_schema stays ProductSchema).
        ConstantName.new(type, namespace:).with_suffix(SCHEMA_SUFFIX).constant
      end

      def self.schema_reference(type, namespace)
        element = element_type(type)
        return if TYPES.key?(element)

        ConstantName.new(element, namespace:).with_suffix(SCHEMA_SUFFIX).relative_path
      end

      def self.element_type(type)
        match = LIST.match(type)
        match ? match[1] : type
      end

      def self.invalid(spec)
        Error.new(%(invalid field "#{spec}" (use name:type, e.g. price:float)))
      end

      private_class_method :type_source, :element_source, :schema_reference, :element_type, :invalid

      def declaration
        line = "field :#{name}, #{type_source}"
        required ? line : "#{line}, required: false"
      end

      def scalar? = TYPES.value?(type_source)
    end
  end
end
