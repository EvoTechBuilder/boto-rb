# frozen_string_literal: true

module Boto
  # A project template. Declared with `Template.define` in a `boto/templates/<name>/template.rb` file.
  class Template < Data.define(:name, :folder, :http, :files, :summary, :source, :legacy_services)
    # Official declarations live inside the core; their files ship with boto-rb-cli.
    OFFICIAL_DIR = File.expand_path("templates", __dir__)
    OFFICIAL_SOURCE = "boto-rb"
    NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
    # Depth from a declaration file up to the root that holds `boto/`: <root>/boto/templates/<name>/template.rb.
    DECLARATION_DEPTH = 4

    # Called by declaration files while the registry loads; the block receives the Builder (the `t` of the DSL).
    def self.define(name, &block)
      path = ::Kernel.caller_locations(1, 1).first.path
      builder = Builder.new(name: name, path: path, source: source_for(path), official: official_path?(path))
      block&.call(builder)
      ::Boto::Templates.add(builder.to_template)
    end

    def self.official_path?(path)
      path.start_with?(File.join(OFFICIAL_DIR, ""))
    end

    def self.source_for(path)
      return OFFICIAL_SOURCE if official_path?(path)

      owner = Gem.loaded_specs.each_value.find { |spec| path.start_with?(File.join(spec.full_gem_path, "")) }
      owner ? owner.name : File.dirname(path, DECLARATION_DEPTH)
    end
  end
end
