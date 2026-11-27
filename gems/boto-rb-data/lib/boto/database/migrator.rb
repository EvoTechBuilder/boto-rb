# frozen_string_literal: true

require "sequel"

module Boto
  module Database
    # Applies the project's timestamped Sequel migrations (db/migrations) to its database.
    class Migrator
      Sequel.extension :migration

      SCHEMA_TABLE = :schema_migrations
      MIGRATION_GLOB = "*.rb"
      UP = :up
      DOWN = :down
      STEPS_MESSAGE = "steps must be a positive Integer"

      def initialize(db, dir)
        @db = db
        @dir = dir
      end

      # Returns the file names applied by this call, in apply order.
      def migrate
        return [] if file_names.empty?

        before = applied_names
        Sequel::TimestampMigrator.run(@db, @dir)
        applied_names - before
      end

      # Returns the file names undone by this call, newest first.
      def rollback(steps: 1)
        validate_steps(steps)
        applied = applied_names
        undone = applied.last(steps)
        return [] if undone.empty?

        # The Sequel target is the version of the last migration that stays applied (0 undoes everything).
        Sequel::TimestampMigrator.run(@db, @dir, target: (applied - undone).last.to_i)
        undone.reverse
      end

      def status
        applied = applied_names
        file_names.map { [_1, applied.include?(_1) ? UP : DOWN] }
      end

      private

      def file_names
        Dir.glob(MIGRATION_GLOB, base: @dir).sort
      end

      # Sorted by name, which is sorted by timestamp.
      def applied_names
        return [] unless @db.table_exists?(SCHEMA_TABLE)

        @db[SCHEMA_TABLE].order(:filename).select_map(:filename)
      end

      def validate_steps(steps)
        return if steps.is_a?(Integer) && steps.positive?

        raise ArgumentError, STEPS_MESSAGE
      end
    end
  end
end
