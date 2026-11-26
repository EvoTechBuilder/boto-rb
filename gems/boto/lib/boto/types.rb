# frozen_string_literal: true

module Boto
  # Shared param types: coercion, restrictions, serialization and JSON Schema.
  module Types
    PATH_SEPARATOR = "."
    INDEX_OPEN = "["

    def self.build(type, min: nil, max: nil, enum: nil, pattern: nil)
      definition = Scalar::DEFINITIONS[type]
      return Scalar.build(definition, min:, max:, enum:, pattern:) if definition
      return List.build(type, min:, max:, enum:, pattern:) if type.is_a?(Array)
      return SchemaRef.build(type, min:, max:, enum:, pattern:) if SchemaRef.schema?(type)

      raise ArgumentError, "unsupported type #{type.inspect}"
    end

    def self.join_path(prefix, path)
      return prefix if path.empty?
      return path if prefix.empty?

      path.start_with?(INDEX_OPEN) ? "#{prefix}#{path}" : "#{prefix}#{PATH_SEPARATOR}#{path}"
    end

    def self.reject_options!(kind, **options)
      options.each do |name, value|
        raise ArgumentError, "#{name} is not supported for #{kind}" unless value.nil?
      end
    end
  end
end
