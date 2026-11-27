# frozen_string_literal: true

module Boto
  module CLI
    module Commands
      class Check < Command
        SUMMARY = "Check that projects only use the projects they reference"
        USAGE = "Usage: boto check [project]"
        POSITION = 6

        def call
          plan = solution
          names = requested_names(plan)
          violations = Boto::Isolation.check(plan, root: cwd, projects: names)
          return report_violations(violations) if violations.any?

          count = (names || plan.projects).size
          out.puts "No isolation violations in #{count} #{count == 1 ? "project" : "projects"}"
          SUCCESS
        end

        private

        def requested_names(plan)
          raise Error, USAGE if argv.size > 1

          name = argv.first
          return unless name

          verify_project(plan, name)
          [name]
        end

        def verify_project(plan, name)
          plan.project(name)
        rescue KeyError
          raise Error, %(unknown project "#{name}")
        end

        def report_violations(violations)
          err.puts Boto::IsolationError.new(violations).message
          FAILURE
        end
      end
    end
  end
end
