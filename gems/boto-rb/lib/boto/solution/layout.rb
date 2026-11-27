# frozen_string_literal: true

module Boto
  # Refuses solutions whose HTTP projects still live in the legacy services/ folder.
  class Layout
    def self.check!(solution, root:)
      legacy = solution.projects.select { legacy?(_1, root) }
      raise LegacyLayoutError.new(legacy) unless legacy.empty?
    end

    def self.legacy?(project, root)
      return false unless project.legacy_path

      File.directory?(File.join(root, project.legacy_path)) &&
        !File.directory?(File.join(root, project.path))
    end
    private_class_method :legacy?
  end
end
