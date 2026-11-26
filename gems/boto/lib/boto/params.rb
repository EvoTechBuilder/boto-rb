# frozen_string_literal: true

module Boto
  # Declares typed request params and extracts them from path, query and body.
  class Params
    Definition = Data.define(:name, :key, :type, :default, :required, :list)

    MISSING = Object.new.freeze
    EMPTY = {}.freeze
    ABSENT_MESSAGE = "is required"

    private_constant :ABSENT_MESSAGE

    def initialize
      @definitions = []
    end

    def declare(name, type, default: MISSING, required: true, **constraints)
      name = name.to_sym
      definition = build_definition(name, type, default, required, constraints)
      raise ArgumentError, "duplicate param #{name}" if names.include?(name)

      @definitions << definition
      self
    end

    def names
      @definitions.map(&:name)
    end

    attr_reader :definitions

    def freeze
      @definitions.freeze
      super
    end

    def call(path:, query:, body:)
      return EMPTY if @definitions.empty?

      values = {}
      errors = nil
      @definitions.each do |definition|
        values[definition.name] = resolve(definition, path, query, body)
      rescue Types::Invalid => e
        errors ||= []
        e.errors.each { |error| errors << error_entry(definition, error) }
      end
      raise Boto::Error::Unprocessable.new(errors) if errors

      values
    end

    private

    def build_definition(name, type, default, required, constraints)
      Definition.new(
        name: name,
        key: name.name,
        type: Types.build(type, **constraints),
        default: default,
        required: required && default.equal?(MISSING),
        list: type.is_a?(Array)
      )
    end

    # Types::Invalid is the error channel, rescued in #call, so the happy path builds no error objects.
    def resolve(definition, path, query, body)
      raw = raw_value(definition, path, query, body)
      return missing_value(definition) if raw.nil?

      definition.type.coerce(wrap_list(definition, raw))
    end

    # Query strings give a single value for a list param (`?ids=1`), so it is wrapped before coercion.
    def wrap_list(definition, raw)
      return raw if !definition.list || raw.is_a?(Array)

      [raw]
    end

    # Precedence: path > query > body. Only nil counts as absent, so false is kept.
    def raw_value(definition, path, query, body)
      value = path[definition.name]
      value = query[definition.key] if value.nil?
      value.nil? ? body[definition.key] : value
    end

    def missing_value(definition)
      return definition.default unless definition.default.equal?(MISSING)
      raise Types::Invalid.single(ABSENT_MESSAGE) if definition.required

      nil
    end

    def error_entry(definition, error)
      { param: Types.join_path(definition.key, error[:path]), message: error[:message] }
    end
  end
end
