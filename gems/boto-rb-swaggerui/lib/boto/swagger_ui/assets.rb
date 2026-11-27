# frozen_string_literal: true

module Boto
  module SwaggerUi
    # Vendored Swagger UI and Boto brand files, read once at load time so requests never touch disk.
    class Assets
      VENDOR_DIR = File.expand_path("../../../vendor/swagger-ui", __dir__)
      BRAND_DIR = File.expand_path("../../../assets", __dir__)
      VERSION_FILE = "VERSION"
      CSS_TYPE = "text/css; charset=utf-8"
      JS_TYPE = "text/javascript; charset=utf-8"
      SVG_TYPE = "image/svg+xml"
      # Maps every servable name to [directory key, content type]; the keys are the only names ever served.
      FILES = {
        "swagger-ui.css" => [:vendor, CSS_TYPE],
        "swagger-ui-bundle.js" => [:vendor, JS_TYPE],
        "swagger-ui-standalone-preset.js" => [:vendor, JS_TYPE],
        "boto.css" => [:brand, CSS_TYPE],
        "ruby.svg" => [:brand, SVG_TYPE]
      }.freeze

      def self.load(vendor_dir: VENDOR_DIR, brand_dir: BRAND_DIR)
        dirs = { vendor: vendor_dir, brand: brand_dir }
        files = FILES.to_h do |name, (dir_key, content_type)|
          [name, [content_type, File.binread(File.join(dirs.fetch(dir_key), name)).freeze].freeze]
        end
        new(version: File.read(File.join(vendor_dir, VERSION_FILE)).strip.freeze, files: files.freeze)
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
