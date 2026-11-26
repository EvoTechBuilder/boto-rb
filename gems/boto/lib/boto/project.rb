# frozen_string_literal: true

module Boto
  class Project < Data.define(:name, :template, :refs, :line)
    TEMPLATE_DIRS = {
      library: "libs",
      webapi: "services",
      microservice: "services",
      worker: "workers",
      web: "apps",
      spa: "apps"
    }.freeze
    PATH_SEPARATOR = "/"
    WORD_SEPARATOR = "_"

    def path
      [TEMPLATE_DIRS.fetch(template), name].join(PATH_SEPARATOR)
    end

    def namespace_name
      name.split(WORD_SEPARATOR).map(&:capitalize).join
    end
  end
end
