# frozen_string_literal: true

module Boto
  # A typed shape for input (coerce) and output (serialize). Subclasses declare fields;
  # compile! generates the per-request methods once, so a request runs direct accessors only.
  class Schema
    class OutputError < StandardError; end

    FIELD_NAME = /\A[a-z_][a-z0-9_]*\z/
    # Methods the schema calls on its instances; a field with one of these names would replace them.
    RESERVED_NAMES = %i[class freeze hash inspect to_h].freeze
    MUST_BE_OBJECT = "must be an object"
    REQUIRED_MESSAGE = "is required"
    REF_PREFIX = "#/components/schemas/"
    NAMESPACE_SEPARATOR = "::"

    Field = Data.define(:name, :key, :type, :required, :declared_type)

    def self.field(name, type, required: true, **constraints)
      raise FrozenError, "#{self} is already compiled" if compiled?

      name = validate_field_name!(name)
      definition = Field.new(
        name:, key: name.to_s.freeze, type: Types.build(type, **constraints),
        required:, declared_type: type
      )
      fields << definition
      attr_reader name
      name
    end

    def self.fields
      @fields ||= []
    end

    def self.compiled?
      @compiled == true
    end

    def self.compile!
      # @compiling guards schemas that reference each other (A -> B -> A).
      return self if compiled? || @compiling

      @compiling = true
      nested_schemas.each(&:compile!)
      fields.freeze
      Compiler.new(self).compile
      @compiled = true
      self
    end

    # Before compile! these call compile!, which defines the generated versions that replace them.
    def self.coerce(input) = compile!.coerce(input)

    def self.serialize(object) = compile!.serialize(object)

    # Memoized only once compiled, when the fields can no longer change.
    def self.json_schema
      return build_json_schema.freeze unless compiled?

      @json_schema ||= build_json_schema.freeze
    end

    def self.json_schema_ref
      @json_schema_ref ||= { "$ref" => "#{REF_PREFIX}#{schema_name}" }.freeze
    end

    # Drops the first namespace segment: Orders::Admin::UserSchema -> AdminUserSchema.
    def self.schema_name
      segments = name.to_s.split(NAMESPACE_SEPARATOR)
      segments.size > 1 ? segments.drop(1).join : name.to_s
    end

    def self.build_json_schema
      schema = { "type" => "object", "properties" => json_properties }
      required = fields.select(&:required).map(&:key)
      schema["required"] = required.freeze unless required.empty?
      schema
    end

    def self.json_properties
      fields.to_h { |field| [field.key, field.type.json_schema] }.freeze
    end

    def self.nested_schemas
      fields.flat_map { |field| schemas_in(field.declared_type) }.uniq
    end

    def self.schemas_in(type)
      case type
      when Array then type.flat_map { |item| schemas_in(item) }
      when Class then Types::SchemaRef.schema?(type) ? [type] : []
      else []
      end
    end

    def self.validate_field_name!(name)
      raise ArgumentError, "invalid field name #{name.inspect}" unless FIELD_NAME.match?(name.to_s)

      symbol = name.to_sym
      raise ArgumentError, "reserved field name #{name}" if RESERVED_NAMES.include?(symbol)
      raise ArgumentError, "duplicate field #{name}" if fields.any? { |field| field.name == symbol }

      symbol
    end

    # Helpers below are private class methods; the generated code calls them with an implicit receiver.
    def self.__boto_require_object(input)
      raise Types::Invalid.single(MUST_BE_OBJECT) unless input.is_a?(Hash)
    end

    def self.__boto_coerce_field(field, input)
      raw = __boto_read_input(input, field)
      return field.type.coerce(raw) unless raw.nil?
      raise Types::Invalid.single(REQUIRED_MESSAGE) if field.required

      nil
    end

    def self.__boto_add_errors(errors, field, invalid)
      errors ||= []
      errors.concat(invalid.errors.map { |error| error.merge(path: Types.join_path(field.key, error[:path])) })
    end

    def self.__boto_dump(field, value)
      return field.type.dump(value) unless value.nil?
      raise OutputError, "#{schema_name}.#{field.name} is required" if field.required

      nil
    end

    def self.__boto_read_input(hash, field)
      hash.key?(field.key) ? hash[field.key] : hash[field.name]
    end

    def self.__boto_read_output(hash, field)
      hash.key?(field.name) ? hash[field.name] : hash[field.key]
    end

    private_class_method :validate_field_name!, :build_json_schema, :json_properties,
                         :nested_schemas, :schemas_in,
                         :__boto_require_object, :__boto_coerce_field, :__boto_add_errors,
                         :__boto_dump, :__boto_read_input, :__boto_read_output

    def ==(other)
      other.class == self.class && other.to_h == to_h
    end
    alias eql? ==

    def hash
      [self.class, to_h].hash
    end

    def inspect
      "#<#{self.class.schema_name} #{inspect_pairs}>"
    end

    private

    def inspect_pairs
      to_h.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")
    end

    def __boto_plain(value)
      case value
      when Schema then value.to_h
      when Array then value.map { |item| __boto_plain(item) }
      else value
      end
    end
  end
end
