# frozen_string_literal: true

module Boto
  module CLI
    module Commands
      class Add < Command
        SUMMARY = "Add a project to the solution"
        USAGE = "Usage: boto add <webapi|library> <name>"
        POSITION = 2
        TEMPLATES = %w[webapi library].freeze

        def call
          template, name = arguments
          project = Boto::Project.new(name: name, template: template.to_sym, refs: [], line: 0)
          ensure_available!(project)
          files = generate(template, project)
          declare!(project)
          files.each { |file| out.puts "create #{project.path}/#{file}" }
          out.puts "update #{BOTOFILE_NAME}"
          SUCCESS
        end

        private

        def arguments
          template, name = argv
          raise Error, USAGE if template.nil? || name.nil?
          raise Error, unknown_template_message(template) unless TEMPLATES.include?(template)
          raise Error, %(invalid project name "#{name}") unless Boto::Botofile::NAME_FORMAT.match?(name)

          [template, name]
        end

        def unknown_template_message(template)
          %(unknown template "#{template}" (available: #{TEMPLATES.join(", ")}))
        end

        def ensure_available!(project)
          if solution.projects.any? { |declared| declared.name == project.name }
            raise Error, %(project "#{project.name}" already exists)
          end
          return unless File.exist?(File.join(cwd, project.path))

          raise Error, %(directory "#{project.path}" already exists)
        end

        def generate(template, project)
          Generator.new(template).generate(
            File.join(cwd, project.path), name: project.name, namespace: project.namespace_name
          )
        end

        # Validates the new Botofile before writing it, so a bad line never reaches disk.
        def declare!(project)
          path = File.join(cwd, BOTOFILE_NAME)
          source = File.read(path)
          source += "\n" unless source.end_with?("\n")
          source += %(project "#{project.name}", template: :#{project.template}\n)
          Boto::Botofile.parse(source, path: path)
          File.write(path, source)
        end
      end
    end
  end
end
