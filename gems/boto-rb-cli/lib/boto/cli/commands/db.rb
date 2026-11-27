# frozen_string_literal: true

require "optparse"

module Boto
  module CLI
    module Commands
      class Db < Command
        SUMMARY = "Apply, undo or list the migrations of the projects with :database"
        USAGE = "Usage: boto db <migrate|rollback|status> [project] [--steps N]"
        POSITION = 10
        MIGRATE = "migrate"
        ROLLBACK = "rollback"
        STATUS = "status"
        SUBCOMMANDS = [MIGRATE, ROLLBACK, STATUS].freeze
        DEFAULT_STEPS = 1
        STEPS_ONLY_FOR_ROLLBACK = "--steps only applies to rollback"
        LIBRARY_MESSAGE = %(boto db needs the boto-rb-data gem: add gem "boto-rb-data" to the Gemfile)
        NO_DATABASE_MESSAGE = %(project "%s" has no :database (add app.use :database, url: ... to its config/app.rb))
        NO_PROJECTS_MESSAGE = "no projects with :database"
        NO_MIGRATIONS_MESSAGE = "%s: no migrations"
        UP_TO_DATE_MESSAGE = "%s: up to date"
        NOTHING_TO_ROLL_BACK_MESSAGE = "%s: nothing to roll back"
        STATUS_LINE = "%<project>s  %<state>-4s  %<file>s"
        OPTIONS = [
          Option.new(key: :steps, flags: %w[--steps], argument: "N", type: Integer,
                     description: "Migrations to undo with rollback (default #{DEFAULT_STEPS})")
        ].freeze
        DEFAULT_REQUIRE_LIBRARY = -> { require DatabaseTasks::LIBRARY }

        def initialize(argv, out:, err:, cwd:, env: ENV, require_library: DEFAULT_REQUIRE_LIBRARY)
          super(argv, out: out, err: err, cwd: cwd)
          @env = env
          @require_library = require_library
        end

        def call
          require_library!
          options = {}
          subcommand, project_name, *extra = parse_arguments(options)
          ensure_usage!(subcommand, project_name, extra)
          steps = steps_for(subcommand, options)
          plan = solution
          tasks = DatabaseTasks.new(plan, boot: Boto::Boot.new(plan, root: cwd, env: @env), root: cwd,
                                          env_name: env_name)
          projects = select_projects(plan, tasks, project_name)
          return report_no_projects if projects.empty?

          projects.each { |name| perform(subcommand, tasks, name, steps) }
          SUCCESS
        end

        private

        # Any LoadError here means the library cannot be used from this project, whatever the missing file is.
        def require_library!
          @require_library.call
        rescue LoadError
          raise Error, LIBRARY_MESSAGE
        end

        def parse_arguments(options)
          option_parser(options).parse(argv)
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def ensure_usage!(subcommand, project_name, extra)
          valid = SUBCOMMANDS.include?(subcommand) && extra.empty?
          raise Error, USAGE unless valid
          raise Error, USAGE if subcommand == ROLLBACK && project_name.nil?
        end

        def steps_for(subcommand, options)
          return DEFAULT_STEPS unless options.key?(:steps)
          raise Error, STEPS_ONLY_FOR_ROLLBACK unless subcommand == ROLLBACK
          raise Error, Boto::Database::Migrator::STEPS_MESSAGE unless options[:steps].positive?

          options[:steps]
        end

        def env_name = @env.fetch(Run::ENV_VARIABLE, Run::DEFAULT_ENV)

        def select_projects(plan, tasks, project_name)
          return [named_database_project(plan, tasks, project_name)] if project_name

          plan.topological_order.map(&:name).select { tasks.database?(_1) }
        end

        def named_database_project(plan, tasks, name)
          plan.project(name)
          raise Error, format(NO_DATABASE_MESSAGE, name) unless tasks.database?(name)

          name
        rescue KeyError
          raise Error, %(unknown project "#{name}")
        end

        def report_no_projects
          out.puts NO_PROJECTS_MESSAGE
          SUCCESS
        end

        def perform(subcommand, tasks, name, steps)
          case subcommand
          when MIGRATE then report_migrated(name, tasks.migrate(name))
          when ROLLBACK then report_rolled_back(name, tasks.rollback(name, steps: steps))
          when STATUS then report_status(name, tasks.status(name))
          end
        rescue Boto::Database::ConnectionError, Sequel::Error => error
          # A database that is down or a broken migration is a usage error here: one line, no backtrace.
          raise Error, "#{name}: #{error.message}"
        end

        def report_migrated(name, applied)
          return out.puts(format(UP_TO_DATE_MESSAGE, name)) if applied.empty?

          applied.each { out.puts "#{name}: migrated #{_1}" }
        end

        def report_rolled_back(name, undone)
          return out.puts(format(NOTHING_TO_ROLL_BACK_MESSAGE, name)) if undone.empty?

          undone.each { out.puts "#{name}: rolled back #{_1}" }
        end

        def report_status(name, statuses)
          return out.puts(format(NO_MIGRATIONS_MESSAGE, name)) if statuses.empty?

          statuses.each do |file, state|
            out.puts format(STATUS_LINE, project: name, state: state, file: file)
          end
        end
      end
    end
  end
end
