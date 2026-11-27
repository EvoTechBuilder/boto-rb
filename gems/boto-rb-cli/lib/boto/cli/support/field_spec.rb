# frozen_string_literal: true

module Boto
  module CLI
    # Parses "name:type" (a trailing "?" makes it optional) and renders the matching schema field line.
    class FieldSpec < Data.define(:name, :type_source, :required)
      IDENTIFIER = /\A[a-z][a-z0-9_]*\z/
      LIST = /\A\[(.+)\]\z/
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

        new(name:, type_source: type_source(type, namespace, spec), required: !spec.end_with?("?"))
      end

      def self.type_source(type, namespace, spec)
        match = LIST.match(type)
        return "[#{element_source(match[1], namespace, spec)}]" if match

        element_source(type, namespace, spec)
      end

      def self.element_source(type, namespace, spec)
        return TYPES[type] if TYPES.key?(type)
        raise invalid(spec) unless IDENTIFIER.match?(type)

        # A name already ending in "schema" is not suffixed twice (product_schema stays ProductSchema).
        ConstantName.new(type, namespace:).with_suffix("schema").constant
      end

      def self.invalid(spec)
        Error.new(%(invalid field "#{spec}" (use name:type, e.g. price:float)))
      end

      private_class_method :type_source, :element_source, :invalid

      def declaration
        line = "field :#{name}, #{type_source}"
        required ? line : "#{line}, required: false"
      end
    end
  end
end
