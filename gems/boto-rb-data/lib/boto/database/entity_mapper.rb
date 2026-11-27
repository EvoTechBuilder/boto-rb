# frozen_string_literal: true

module Boto
  module Database
    # Turns a row (a Hash keyed by column Symbols) into an entity. Columns the entity does not declare are ignored.
    class EntityMapper
      attr_reader :entity, :members

      def initialize(entity)
        @entity = entity
        @members = entity.members.freeze
      end

      def build(row)
        entity.new(**row.slice(*members))
      end

      # Accepts a String or a Symbol, so filters and order fields can come from a request.
      def member(name)
        key = name.is_a?(String) ? name.to_sym : name
        return key if members.include?(key)

        raise ArgumentError, %(unknown field "#{name}" for #{entity})
      end

      def missing_columns(columns)
        members - columns
      end
    end
  end
end
