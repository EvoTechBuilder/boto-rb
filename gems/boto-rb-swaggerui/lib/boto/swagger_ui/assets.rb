# frozen_string_literal: true

module Boto
  module SwaggerUi
    # Vendored Swagger UI files, read once at load time so requests never touch disk.
    class Assets
      DIR = File.expand_path("../../../vendor/swagger-ui", __dir__)
      VERSION_FILE = "VERSION"
      FILES = {
        "swagger-ui.css" => "text/css; charset=utf-8",
        "swagger-ui-bundle.js" => "text/javascript; charset=utf-8"
      }.freeze

      def self.load(dir: DIR)
        files = FILES.to_h do |name, content_type|
          [name, [content_type, File.binread(File.join(dir, name)).freeze].freeze]
        end
        new(version: File.read(File.join(dir, VERSION_FILE)).strip.freeze, files: files.freeze)
      end

      attr_reader :version

      def initialize(version:, files:)
        @version = version
        @files = files
        freeze
      end

      # Returns [content_type, body] for a known name, or nil; the name is only a hash key, never a path.
      def fetch(name)
        @files[name]
      end
    end
  end
end
