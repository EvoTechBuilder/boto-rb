# frozen_string_literal: true

require "open3"
require "optparse"
require "rbconfig"

module Boto
  module CLI
    module Commands
      class Test < Command
        SUMMARY = "Run the tests of the solution's projects"
        USAGE = "Usage: boto test [project] [--affected] [--base REF]"
        POSITION = 8
        CONFLICT_MESSAGE = "a project cannot be combined with --affected"
        DEFAULT_BASE = "main"
        OPTIONS = [
          Option.new(key: :affected, flags: %w[--affected],
                     description: "Only projects affected by changes since the base ref"),
          Option.new(key: :base, flags: %w[--base], argument: "REF",
                     description: "Git ref to compare with (default #{DEFAULT_BASE})")
        ].freeze
        TEST_DIR = "test"
        TEST_LOADER = 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
        # --relative keeps paths relative to the solution root even when it is a subfolder of the repo.
        GIT_DIFF = %w[git diff --name-only --relative].freeze
        GIT_UNTRACKED = %w[git ls-files --others --exclude-standard].freeze

        DEFAULT_PROCESS_RUNNER = ->(command, chdir:) { system(*command, chdir: chdir) }
        DEFAULT_CHANGED_FILES = lambda do |base, cwd|
          commands = [GIT_DIFF + [base], GIT_UNTRACKED]
          lines = commands.flat_map do |command|
            stdout, stderr, status = Open3.capture3(*command, chdir: cwd)
            raise Error, "git failed: #{stderr.strip}" unless status.success?

            stdout.lines(chomp: true)
          end
          lines.reject(&:empty?).uniq
        end

        def initialize(argv, out:, err:, cwd:, process_runner: DEFAULT_PROCESS_RUNNER,
                       changed_files: DEFAULT_CHANGED_FILES)
          super(argv, out: out, err: err, cwd: cwd)
          @process_runner = process_runner
          @changed_files = changed_files
        end

        def call
          options = parse_options
          plan = solution
          projects = select_projects(options, plan)
          return report_empty if projects.empty?

          failed = projects.filter_map { |project| project.name unless run_project(project) }
          report(projects.count { |project| test_dir?(project) }, failed)
        end

        private

        def parse_options
          options = { affected: false, base: DEFAULT_BASE }
          positional = option_parser(options).parse(argv)
          raise Error, USAGE if positional.size > 1

          options.merge(project: positional.first)
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def select_projects(options, plan)
          raise Error, CONFLICT_MESSAGE if options[:project] && options[:affected]
          return [named_project(plan, options[:project])] if options[:project]
          return affected_projects(plan, options[:base]) if options[:affected]

          plan.topological_order
        end

        def named_project(plan, name)
          plan.project(name)
        rescue KeyError
          raise Error, %(unknown project "#{name}")
        end

        def affected_projects(plan, base)
          names = AffectedProjects.call(@changed_files.call(base, cwd), plan)
          names.map { |name| plan.project(name) }
        end

        def run_project(project)
          return skip(project) unless test_dir?(project)

          out.puts "== #{project.name}"
          @process_runner.call([RbConfig.ruby, "-Itest", "-e", TEST_LOADER], chdir: project_dir(project))
        end

        def skip(project)
          out.puts "-- skip #{project.name} (no test/)"
          true
        end

        def test_dir?(project)
          File.directory?(File.join(project_dir(project), TEST_DIR))
        end

        def project_dir(project)
          File.join(cwd, project.path)
        end

        def report_empty
          out.puts "no projects to test"
          SUCCESS
        end

        def report(tested_count, failed)
          out.puts "#{tested_count} #{tested_count == 1 ? "project" : "projects"} tested, #{failed.size} failed"
          out.puts "failed: #{failed.join(", ")}" if failed.any?
          failed.empty? ? SUCCESS : FAILURE
        end
      end
    end
  end
end
