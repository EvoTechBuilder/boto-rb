# frozen_string_literal: true

module Boto
  class Project < Data.define(:name, :template, :refs, :line, :generators)
    # Code folders loaded under the project namespace; every tool reads this list.
    CODE_DIRS = %w[endpoints operations models repositories schemas].freeze
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
      [::Boto::Templates.fetch(template).folder, name].join(PATH_SEPARATOR)
    end

    # Where HTTP projects lived before `apps/`; nil for the other templates.
    def legacy_path
      return unless ::Boto::Templates.fetch(template).legacy_services

      [LEGACY_HTTP_DIR, name].join(PATH_SEPARATOR)
    end

    def namespace_name
      self.class.namespace_for(name)
    end
  end
end
