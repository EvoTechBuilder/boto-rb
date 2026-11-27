# frozen_string_literal: true

require "json"
require "optparse"

module Boto
  module CLI
    module Commands
      class Openapi < Command
        SUMMARY = "Print or write the OpenAPI document of a project"
        USAGE = "Usage: boto openapi <project> [-o FILE] [--api-version V]"
        POSITION = 9
        DEFAULT_API_VERSION = "0.1.0"
        # Documentation needs the routes, not production secrets, so the app boots as in development.
        ENV_NAME = "development"
        OPTIONS = [
          Option.new(key: :output, flags: %w[-o --output], argument: "FILE",
                     description: "Write the document to FILE instead of stdout"),
          Option.new(key: :api_version, flags: %w[--api-version], argument: "V",
                     description: "Version written to info.version (default #{DEFAULT_API_VERSION})")
        ].freeze

        def call
          options = parse_options
          plan = solution
          project = named_project(plan, options[:project])
          boot = Boto::Boot.new(plan, root: cwd)
          emit(JSON.pretty_generate(document(boot, project, options[:api_version])), options[:output])
          SUCCESS
        ensure
          # Releases the Zeitwerk loaders so the same solution can be booted again in this process.
          boot&.shutdown
        end

        private

        def parse_options
          options = { api_version: DEFAULT_API_VERSION }
          positional = option_parser(options).parse(argv)
          raise Error, USAGE unless positional.size == 1

          options.merge(project: positional.first)
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def named_project(plan, name)
          project = plan.projects.find { |declared| declared.name == name }
          raise Error, %(unknown project "#{name}") unless project
          raise Error, %(project "#{name}" (#{project.template}) has no endpoints) unless endpoints?(project)

          project
        end

        def endpoints?(project)
          Boto::Templates.http?(project.template)
        end

        def document(boot, project, api_version)
          app = boot.app(project.name, env_name: ENV_NAME, error_output: err)
          Boto::OpenAPI.generate(app, title: project.name, version: api_version)
        end

        def emit(json, output)
          return out.puts(json) unless output

          File.write(File.expand_path(output, cwd), "#{json}\n")
          out.puts "write #{output}"
        rescue SystemCallError => e
          raise Error, "cannot write #{output}: #{e.message}"
        end
      end
    end
  end
end
