# frozen_string_literal: true

module Boto
  # Read access to one table, with rows mapped to an entity (a Data). Repositories are classes, each one a
  # direct subclass of Boto::Repository, because the boot check finds them through Class#subclasses.
  class Repository
    extend Reading
    extend Writing

    DEFAULT_CLOCK = -> { Time.now }

    class << self
      # Replaced in tests, so timestamps can be checked without waiting on the real time.
      attr_writer :clock

      def clock = @clock || DEFAULT_CLOCK

      # Defines find_by_<member> for every member here, at boot, so no request reflects on the entity.
      def entity(entity_class)
        @mapper = Boto::Database::EntityMapper.new(entity_class)
        entity_class.members.each { |member| define_finder(member) }
      end

      def table(name)
        @table = name
      end

      def declared?
        !@mapper.nil? && !@table.nil?
      end

      # Raises on the first entity member that is not a column of the table.
      def check!(db)
        raise SchemaMismatch, "#{name}: table #{table_name} does not exist" unless db.table_exists?(table_name)

        column = mapper.missing_columns(db.schema(table_name).map(&:first)).first
        return unless column

        raise SchemaMismatch, %(#{name}: column "#{column}" of #{mapper.entity} is missing in table #{table_name})
      end

      private

      def define_finder(member)
        define_singleton_method(:"find_by_#{member}") { |value| find_by(member, value) }
      end

      def mapper
        @mapper || raise(MissingDeclarationError, "#{name} has no entity; declare it with `entity YourData`")
      end

      def table_name
        @table || raise(MissingDeclarationError, "#{name} has no table; declare it with `table :name`")
      end

      def dataset
        database[table_name]
      end

      # Asked on every call, never memorized: a reload replaces the connection.
      def database
        Boto::Database::Connections.for(namespace)
      end

      # The project owning the class is the first segment of its name (Catalogo::ProductRepository -> Catalogo).
      def namespace
        @namespace ||= Object.const_get(name.split("::").first)
      end
    end
  end
end
