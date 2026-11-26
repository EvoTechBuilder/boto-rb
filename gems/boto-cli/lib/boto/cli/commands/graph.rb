# frozen_string_literal: true

module Boto
  module CLI
    module Commands
      class Graph < Command
        SUMMARY = "Show the dependency graph of the solution"
        PROJECT_INDENT = "  "
        REF_INDENT = "    "
        REF_PREFIX = "-> "
        NO_PROJECTS = "(no projects)"

        def call
          graph = solution
          out.puts "solution #{graph.name}"
          print_projects(graph.topological_order)
          SUCCESS
        end

        private

        def print_projects(projects)
          return out.puts("#{PROJECT_INDENT}#{NO_PROJECTS}") if projects.empty?

          projects.each { |project| print_project(project) }
        end

        def print_project(project)
          out.puts "#{PROJECT_INDENT}#{project.name} [#{project.template}]"
          project.refs.each { |ref| out.puts "#{REF_INDENT}#{REF_PREFIX}#{ref}" }
        end
      end
    end
  end
end
