# frozen_string_literal: true

module Boto
  module CLI
    # Turns `boto generate migration <project> <name>` into a timestamped file in db/migrations. Migrations have no test.
    class MigrationBlueprint
      KIND = "migration"
      FOLDER = File.join("db", "migrations")
      SOURCE_TEMPLATE = "file.rb.erb"
      # Plain snake_case only: a "/" would put the timestamp in a folder name.
      NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/
      NAME_MESSAGE = %(invalid migration name "%s" (use lowercase snake_case, e.g. create_products))
      # Sorting by file name is sorting by time, which is what Sequel's TimestampMigrator relies on.
      TIMESTAMP_FORMAT = "%Y%m%d%H%M%S"

      def initialize(name:, clock:)
        raise Error, format(NAME_MESSAGE, name) unless NAME_PATTERN.match?(name)

        @name = name
        @clock = clock
      end

      # Migrations define no constant, so there is nothing to clash with.
      def constant = nil

      def files(with_test: false)
        [GeneratedFile.new(path: File.join(FOLDER, "#{timestamp}_#{@name}.rb"), content: render)]
      end

      private

      def timestamp = @clock.now.utc.strftime(TIMESTAMP_FORMAT)

      def render = Blueprint.render(KIND, SOURCE_TEMPLATE, {})
    end
  end
end
