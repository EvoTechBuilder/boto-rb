# frozen_string_literal: true

module Boto
  module Types
    # A scalar type: coercion, restrictions, dump and JSON Schema, driven by a DEFINITIONS entry.
    class Scalar
      Definition = Data.define(:coercer, :message, :json, :dumper, :unit)

      IDENTITY = ->(value) { value }
      DATE_DUMPER = ->(value) { value.iso8601 }
      TIME_DUMPER = ->(value) { value.iso8601(3) }
      STRING_JSON = { "type" => "string" }.freeze
      DATE_JSON = { "type" => "string", "format" => "date" }.freeze
      TIME_JSON = { "type" => "string", "format" => "date-time" }.freeze

      DEFINITIONS = {
        String => Definition.new(
          coercer: Coercion.method(:string), message: "must be a String",
          json: STRING_JSON, dumper: IDENTITY, unit: :characters
        ),
        Integer => Definition.new(
          coercer: Coercion.method(:integer), message: "must be an Integer",
          json: { "type" => "integer" }.freeze, dumper: IDENTITY, unit: :number
        ),
        Float => Definition.new(
          coercer: Coercion.method(:float), message: "must be a Float",
          json: { "type" => "number" }.freeze, dumper: IDENTITY, unit: :number
        ),
        Boto::Boolean => Definition.new(
          coercer: Coercion.method(:boolean), message: "must be a boolean",
          json: { "type" => "boolean" }.freeze, dumper: IDENTITY, unit: nil
        ),
        Date => Definition.new(
          coercer: Coercion.method(:date), message: "must be a date (YYYY-MM-DD)",
          json: DATE_JSON, dumper: DATE_DUMPER, unit: nil
        ),
        Time => Definition.new(
          coercer: Coercion.method(:time), message: "must be a date-time (ISO 8601 with time zone)",
          json: TIME_JSON, dumper: TIME_DUMPER, unit: nil
        )
      }.freeze

      attr_reader :json_schema

      def self.build(definition, min: nil, max: nil, enum: nil, pattern: nil)
        enum_rules = enum.nil? ? nil : Enum.new(enum, definition)
        constraints = Constraints.new(unit: definition.unit, min:, max:, pattern:, enum: enum_rules)
        new(definition, constraints)
      end

      def initialize(definition, constraints)
        @definition = definition
        @constraints = constraints
        @json_schema = definition.json.merge(constraints.json_keywords).freeze
        freeze
      end

      def coerce(value)
        coerced = @definition.coercer.call(value)
        raise Invalid.single(@definition.message) if coerced.nil?

        message = @constraints.violation(coerced)
        raise Invalid.single(message) if message

        coerced
      end

      def dump(value)
        @definition.dumper.call(value)
      end
    end
  end
end
