# frozen_string_literal: true

module Boto
  # Declares typed request params and extracts them from path, query and body.
  class Params
    Definition = Data.define(:name, :key, :coercer, :default, :required)

    MISSING = Object.new.freeze
    EMPTY = {}.freeze
    INTEGER_PATTERN = /\A-?\d+\z/

    COERCE_INTEGER = lambda do |value|
      return value if value.is_a?(Integer)
      return Integer(value, 10) if value.is_a?(String) && INTEGER_PATTERN.match?(value)

      raise ArgumentError, "must be an Integer"
    end

    COERCE_FLOAT = lambda do |value|
      case value
      when Integer, Float then value.to_f
      when String then Float(value, exception: false)
      end || raise(ArgumentError, "must be a Float")
    end

    COERCERS = {
      String => lambda do |value|
        raise ArgumentError, "must be a String" unless value.is_a?(String)

        value
      end,
      Integer => COERCE_INTEGER,
      Float => COERCE_FLOAT,
      Boto::Boolean => ->(value) { Boto::Boolean.coerce(value) }
    }.freeze

    private_constant :INTEGER_PATTERN, :COERCE_INTEGER, :COERCE_FLOAT

    def initialize
      @definitions = []
    end

    def declare(name, type, default: MISSING, required: true)
      name = name.to_sym
      coercer = COERCERS.fetch(type) { raise ArgumentError, "unsupported param type #{type.inspect}" }
      raise ArgumentError, "duplicate param #{name}" if names.include?(name)

      @definitions << build_definition(name, coercer, default, required)
      self
    end

    def names
      @definitions.map(&:name)
    end

    def freeze
      @definitions.freeze
      super
    end

    def call(path:, query:, body:)
      return EMPTY if @definitions.empty?

      errors = []
      values = @definitions.to_h do |definition|
        [definition.name, resolve(definition, path, query, body, errors)]
      end
      raise Boto::Error::Unprocessable.new(errors) unless errors.empty?

      values
    end

    private

    def build_definition(name, coercer, default, required)
      Definition.new(
        name: name,
        key: name.name,
        coercer: coercer,
        default: default,
        required: required && default.equal?(MISSING)
      )
    end

    def resolve(definition, path, query, body, errors)
      raw = raw_value(definition, path, query, body)
      return missing_value(definition, errors) if raw.nil?

      definition.coercer.call(raw)
    rescue ArgumentError => e
      errors << { param: definition.key, message: e.message }
      nil
    end

    # Precedence: path > query > body. Only nil counts as absent, so false is kept.
    def raw_value(definition, path, query, body)
      value = path[definition.name]
      value = query[definition.key] if value.nil?
      value.nil? ? body[definition.key] : value
    end

    def missing_value(definition, errors)
      return definition.default unless definition.default.equal?(MISSING)

      errors << { param: definition.key, message: "is required" } if definition.required
      nil
    end
  end
end
