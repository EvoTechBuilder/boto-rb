# frozen_string_literal: true

require "optparse"

module Boto
  module CLI
    module Commands
      class Generate < Command
        SUMMARY = "Generate a schema, model, endpoint or operation with its test"
        USAGE = "Usage: boto generate <schema|model|endpoint|operation> <project> <name> [args] " \
                "[--skip-tests] [--force]"
        POSITION = 4
        OPTIONS = [
          Option.new(key: :skip_tests, flags: %w[--skip-tests], description: "Do not generate the test file"),
          Option.new(key: :force, flags: %w[--force], description: "Overwrite files that already exist"),
          Option.new(key: :body, flags: %w[--body], argument: "NAME",
                     description: "Schema of the request body (endpoint)"),
          Option.new(key: :returns, flags: %w[--returns], argument: "NAME",
                     description: "Schema of the response, [NAME] for a list (endpoint)")
        ].freeze

        def call
          options = {}
          kind, project_name, name, *args = parse_arguments(options)
          raise Error, USAGE if [kind, project_name, name].any?(&:nil?)

          ensure_kind!(kind)
          plan = solution
          project = find_project(plan, project_name)
          blueprint = build_blueprint(project, kind, name, args, options)
          files = blueprint.files(with_test: with_test?(plan, project, options))
          ensure_writable!(project, files, force: options[:force])
          ensure_no_clash!(project, files, blueprint.constant)
          write_files(project, files)
          SUCCESS
        end

        private

        def parse_arguments(options)
          option_parser(options).parse(argv)
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def ensure_kind!(kind)
          return if Blueprint::KINDS.key?(kind)

          raise Error, %(unknown generator "#{kind}" (available: #{Blueprint::KINDS.keys.join(", ")}))
        end

        def find_project(plan, name)
          project = plan.projects.find { |declared| declared.name == name }
          raise Error, %(unknown project "#{name}") unless project

          project
        end

        def build_blueprint(project, kind, name, args, options)
          folder = ProjectFolder.new(project_dir(project))
          BlueprintBuilder.new(project: project, folder: folder).build(kind, name, args, options)
        end

        def with_test?(plan, project, options)
          !options[:skip_tests] && plan.generate_tests?(project.name)
        end

        # Checks every path before the first write, so a refused run leaves the project untouched.
        def ensure_writable!(project, files, force:)
          dir = project_dir(project)
          files.each { |file| file.target(dir) }
          return if force

          existing = files.find { |file| file.exist?(dir) }
          return unless existing

          raise Error, %(#{shown_path(project, existing)} already exists (use --force to overwrite))
        end

        # Runs even with --force: --force replaces only this command's own file, never a file in another folder.
        def ensure_no_clash!(project, files, constant)
          folder = ProjectFolder.new(project_dir(project))
          files.each do |file|
            clash = folder.clashing_path(file)
            raise Error, "#{constant} already exists in #{File.join(project.path, clash)}" if clash
          end
        end

        def write_files(project, files)
          files.each do |file|
            file.write(project_dir(project))
            out.puts "create #{shown_path(project, file)}"
          end
        end

        def project_dir(project) = File.join(cwd, project.path)

        def shown_path(project, file) = File.join(project.path, file.path)
      end
    end
  end
end
