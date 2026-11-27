# frozen_string_literal: true

module Boto
  module CLI
    # Turns `boto generate repository <project> <entity>` into the repository file and its test.
    class RepositoryBlueprint
      SUFFIX = "repository"
      FOLDER = "repositories"
      TEST_DIR = "test"
      TEST_SUFFIX = "_test"
      TEST_CLASS_SUFFIX = "Test"
      # Table names are the plural of the last name segment, so "products/item" maps to "items".
      PLURAL_SUFFIX = "s"
      TABLE_PATTERN = /\A[a-z][a-z0-9_]*\z/
      NAME_MESSAGE = "repository names are entity names, so write product instead of product_repository"
      TABLE_MESSAGE = %(invalid table "%s" (use lowercase snake_case))

      def initialize(name:, namespace:, table: nil)
        raise Error, NAME_MESSAGE if name.end_with?("_#{SUFFIX}")

        @entity = ConstantName.new(name, namespace: namespace)
        @repository = ConstantName.new("#{name}_#{SUFFIX}", namespace: namespace)
        @table = table || default_table(name)
        raise Error, format(TABLE_MESSAGE, @table) unless TABLE_PATTERN.match?(@table)
      end

      def constant = @repository.constant

      def files(with_test:)
        return [source_file] unless with_test

        [source_file, test_file]
      end

      private

      def default_table(name) = "#{name.split("/").last}#{PLURAL_SUFFIX}"

      def source_file
        GeneratedFile.new(path: File.join(FOLDER, "#{@repository.relative_path}.rb"), content: render("file.rb.erb"))
      end

      def test_file
        path = File.join(TEST_DIR, FOLDER, "#{@repository.relative_path}#{TEST_SUFFIX}.rb")
        GeneratedFile.new(path: path, content: render("test.rb.erb"))
      end

      def render(template)
        Blueprint.render("repository", template, locals)
      end

      def locals
        {
          constant: constant,
          entity: @entity.constant,
          table: @table,
          test_class: "#{constant}#{TEST_CLASS_SUFFIX}"
        }
      end
    end
  end
end
