# frozen_string_literal: true

require "optparse"

module Boto
  module CLI
    module Commands
      class Add < Command
        SUMMARY = "Add a project to the solution"
        USAGE = "Usage: boto add <template> <name> [--refs a,b]"
        POSITION = 2
        REFS_SEPARATOR = ","
        OPTIONS = [
          Option.new(key: :refs, flags: %w[--refs], argument: "a,b",
                     description: "Projects it references, separated by commas")
        ].freeze

        def self.help = "#{super}\n\nTemplates: #{generatable_names.join(", ")}"

        def self.generatable_names
          Boto::Templates.all.select { |template| Generator.available?(template) }.map(&:name)
        end

        def call
          template, project = project_from_arguments
          ensure_available!(project)
          source = botofile_with(project)
          files = generate(template, project)
          File.write(botofile_path, source)
          files.each { |file| out.puts "create #{project.path}/#{file}" }
          out.puts "update #{BOTOFILE_NAME}"
          SUCCESS
        end

        private

        def project_from_arguments
          values = {}
          positional = option_parser(values).parse(argv)
          raise Error, USAGE unless positional.size == 2

          build_project(*positional, refs: refs_from(values[:refs]))
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def build_project(template_name, name, refs:)
          template = template_for(template_name)
          raise Error, %(invalid project name "#{name}") unless Boto::Botofile::NAME_FORMAT.match?(name)

          ensure_refs_declared!(refs)
          [template, Boto::Project.new(name: name, template: template.name, refs: refs, line: 0)]
        end

        def template_for(name)
          raise Error, Boto::Templates.unknown_message(name) unless Boto::Templates.key?(name)

          template = Boto::Templates.fetch(name)
          raise Error, "template :#{template.name} has no files yet" unless Generator.available?(template)

          template
        end

        def refs_from(value)
          return [] if value.nil?

          refs = value.split(REFS_SEPARATOR, -1)
          raise Error, %(invalid refs "#{value}") if refs.empty? || refs.any?(&:empty?)

          refs
        end

        def ensure_refs_declared!(refs)
          declared = solution.projects.map(&:name)
          unknown = refs.find { |ref| !declared.include?(ref) }
          raise Error, %(unknown project "#{unknown}") if unknown
        end

        def ensure_available!(project)
          if solution.projects.any? { |declared| declared.name == project.name }
            raise Error, %(project "#{project.name}" already exists)
          end
          return unless File.exist?(File.join(cwd, project.path))

          raise Error, %(directory "#{project.path}" already exists)
        end

        def generate(template, project)
          Generator.for_template(template).generate(File.join(cwd, project.path), template_locals(project))
        end

        def template_locals(project)
          { name: project.name, namespace: project.namespace_name, refs: project.refs,
            template: project.template, boto_version: Boto::CLI::VERSION }
        end

        # Parses the new Botofile before anything is written, so a bad line never reaches disk.
        def botofile_with(project)
          source = File.read(botofile_path)
          source += "\n" unless source.end_with?("\n")
          source += declaration(project)
          Boto::Botofile.parse(source, path: botofile_path)
          source
        end

        def declaration(project)
          refs = project.refs.empty? ? "" : ", refs: %w[#{project.refs.join(" ")}]"
          %(project "#{project.name}", template: :#{project.template}#{refs}\n)
        end

        def botofile_path = File.join(cwd, BOTOFILE_NAME)
      end
    end
  end
end
