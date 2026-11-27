# frozen_string_literal: true

module Boto
  class LegacyLayoutError < StandardError
    HEADER = %(project "%<name>s" is in %<legacy>s; HTTP projects now live in %<path>s.)
    FIX = "Fix: git mv %<legacy>s %<path>s"
    SEPARATOR = "\n"

    attr_reader :projects

    def initialize(projects)
      @projects = projects.map(&:name).freeze
      super(build_message(projects))
    end

    private

    def build_message(projects)
      projects.map { project_block(_1) }.join(SEPARATOR)
    end

    def project_block(project)
      values = { name: project.name, legacy: project.legacy_path, path: project.path }
      [format(HEADER, values), format(FIX, values)].join(SEPARATOR)
    end
  end
end
