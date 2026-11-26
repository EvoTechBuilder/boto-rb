# frozen_string_literal: true

module Boto
  module CLI
    # Pure selection: which projects a set of changed files touches, dependents included.
    module AffectedProjects
      BOTOFILE = "Botofile"

      module_function

      def call(changed_files, solution)
        return solution.topological_order.map(&:name) if changed_files.include?(BOTOFILE)

        selected = directly_changed(changed_files, solution).flat_map do |name|
          [name, *solution.dependents_of(name)]
        end
        solution.topological_order.map(&:name).select { |name| selected.include?(name) }
      end

      def directly_changed(changed_files, solution)
        solution.projects.filter_map do |project|
          prefix = "#{project.path}/"
          project.name if changed_files.any? { |file| file.start_with?(prefix) }
        end
      end
      private_class_method :directly_changed
    end
  end
end
