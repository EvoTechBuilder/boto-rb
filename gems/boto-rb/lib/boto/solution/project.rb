# frozen_string_literal: true

module Boto
  class Project < Data.define(:name, :template, :refs, :line, :generators)
    TEMPLATE_DIRS = {
      library: "libs",
      webapi: "apps",
      microservice: "apps",
      worker: "workers",
      web: "apps",
      spa: "apps"
    }.freeze
    HTTP_TEMPLATES = %i[webapi microservice].freeze
    LEGACY_HTTP_DIR = "services"
    PATH_SEPARATOR = "/"
    WORD_SEPARATOR = "_"

    def initialize(name:, template:, refs:, line:, generators: {})
      super(name: name, template: template, refs: refs, line: line, generators: generators.dup.freeze)
    end

    def self.namespace_for(name)
      name.split(WORD_SEPARATOR).map(&:capitalize).join
    end

    def path
      [TEMPLATE_DIRS.fetch(template), name].join(PATH_SEPARATOR)
    end

    # Where HTTP projects lived before `apps/`; nil for the other templates.
    def legacy_path
      return unless HTTP_TEMPLATES.include?(template)

      [LEGACY_HTTP_DIR, name].join(PATH_SEPARATOR)
    end

    def namespace_name
      self.class.namespace_for(name)
    end
  end
end
