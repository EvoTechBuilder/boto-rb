# frozen_string_literal: true

require "erb"

module Boto
  module CLI
    # Turns a kind, a name and its fields into the files to write: the source file and, optionally, its test.
    class Blueprint
      TEMPLATES_ROOT = File.expand_path("../../../../templates/generate", __dir__)
      TEMPLATE_TRIM_MODE = "-"
      SOURCE_TEMPLATE = "file.rb.erb"
      TEST_TEMPLATE = "test.rb.erb"
      TEST_DIR = "test"
      TEST_SUFFIX = "_test"
      TEST_CLASS_SUFFIX = "Test"
      # The dispatch by kind: the folder of the files under the project, and the suffix of the names (nil for none).
      KINDS = {
        "schema" => { folder: "schemas", suffix: "schema" },
        "model" => { folder: "models", suffix: nil }
      }.freeze

      attr_reader :kind, :item, :fields

      def initialize(kind, name:, fields:, namespace:)
        @kind = kind
        @settings = KINDS.fetch(kind)
        @item = named(name, namespace)
        @fields = fields
      end

      def files(with_test:)
        return [source_file] unless with_test

        [source_file, test_file]
      end

      private

      def named(name, namespace)
        constant_name = ConstantName.new(name, namespace: namespace)
        suffix = @settings[:suffix]
        suffix ? constant_name.with_suffix(suffix) : constant_name
      end

      def folder = @settings.fetch(:folder)

      def source_file
        GeneratedFile.new(path: File.join(folder, "#{item.relative_path}.rb"), content: render(SOURCE_TEMPLATE))
      end

      def test_file
        path = File.join(TEST_DIR, folder, "#{item.relative_path}#{TEST_SUFFIX}.rb")
        GeneratedFile.new(path: path, content: render(TEST_TEMPLATE))
      end

      def render(template)
        source = File.read(File.join(TEMPLATES_ROOT, kind, template))
        ERB.new(source, trim_mode: TEMPLATE_TRIM_MODE).result_with_hash(locals)
      end

      def locals
        {
          constant: item.constant,
          test_class: "#{item.constant}#{TEST_CLASS_SUFFIX}",
          declarations: fields.map(&:declaration),
          members: fields.map { ":#{_1.name}" }.join(", ")
        }
      end
    end
  end
end
