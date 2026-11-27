# frozen_string_literal: true

module Boto
  module CLI
    # Runs the migrations of the projects that declare :database, for `boto db` and `boto test`.
    # Only the configuration is read to find the URL: the plugin is never started, because its
    # table check would fail before the first migration has run.
    class DatabaseTasks
      LIBRARY = "boto/database"
      PLUGIN = :database
      MIGRATIONS_DIR = File.join("db", "migrations")

      def initialize(plan, boot:, root:, env_name:)
        @plan = plan
        @boot = boot
        @root = root
        @env_name = env_name
      end

      def database?(name)
        !plugin_for(name).nil?
      end

      # Each method returns the file names it touched, in the order they were applied or undone.
      def migrate(name) = with_migrator(name, &:migrate)

      def rollback(name, steps:) = with_migrator(name) { _1.rollback(steps: steps) }

      def status(name) = with_migrator(name, &:status)

      private

      def plugin_for(name)
        @boot.configuration(name, env_name: @env_name).build_only(PLUGIN)
      end

      def with_migrator(name)
        database = plugin_for(name).open_connection
        yield Boto::Database::Migrator.new(database, migrations_dir(name))
      ensure
        database&.disconnect
      end

      def migrations_dir(name)
        File.join(@root, @plan.project(name).path, MIGRATIONS_DIR)
      end
    end
  end
end
