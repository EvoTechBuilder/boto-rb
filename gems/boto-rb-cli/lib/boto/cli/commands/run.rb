# frozen_string_literal: true

require "optparse"

module Boto
  module CLI
    module Commands
      class Run < Command
        SUMMARY = "Run the solution's services in one process"
        USAGE = "Usage: boto run [project] [--port N] [--host H]"
        POSITION = 6
        SERVABLE_TEMPLATES = %i[webapi microservice].freeze
        DEFAULT_PORT = 3000
        DEFAULT_ENV = "development"
        ENV_VARIABLE = "BOTO_ENV"
        VALID_PORTS = (1..65_535)
        STOP_MESSAGE = "Stopping"
        OPTIONS = [
          Option.new(key: :port, flags: %w[--port], argument: "N", type: Integer,
                     description: "First port; each service gets the next one (default #{DEFAULT_PORT})"),
          Option.new(key: :host, flags: %w[--host], argument: "H",
                     description: "Host to bind (default #{Boto::CLI::Server::DEFAULT_HOST})")
        ].freeze

        DEFAULT_SERVER_FACTORY = ->(apps_by_port, host:) { Boto::CLI::Server.new(apps_by_port, host:) }

        def initialize(argv, out:, err:, cwd:, server_factory: DEFAULT_SERVER_FACTORY, env: ENV)
          super(argv, out: out, err: err, cwd: cwd)
          @server_factory = server_factory
          @env = env
        end

        def call
          options = parse_options
          plan = solution
          ports = port_assignments(select_projects(plan, options[:project]), options[:port])
          boot = Boto::Boot.new(plan, root: cwd)
          serve(boot, ports, options[:host])
        ensure
          # Releases the Zeitwerk loaders so the same solution can be booted again in this process.
          boot&.shutdown
        end

        private

        attr_reader :server_factory, :env

        def parse_options
          options = { port: DEFAULT_PORT, host: Boto::CLI::Server::DEFAULT_HOST }
          positional = option_parser(options).parse(argv)
          raise Error, USAGE if positional.size > 1
          raise Error, %(invalid port "#{options[:port]}") unless VALID_PORTS.cover?(options[:port])

          options.merge(project: positional.first)
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def select_projects(plan, name)
          return [named_project(plan, name)] if name

          servable = plan.topological_order.select { |project| servable?(project) }
          raise Error, "no servable projects (#{SERVABLE_TEMPLATES.join(", ")})" if servable.empty?

          servable
        end

        def named_project(plan, name)
          project = plan.projects.find { |declared| declared.name == name }
          raise Error, %(unknown project "#{name}") unless project
          raise Error, %(project "#{name}" (#{project.template}) cannot be served) unless servable?(project)

          project
        end

        def servable?(project)
          SERVABLE_TEMPLATES.include?(project.template)
        end

        # Ports follow the topological order, so a dependency always gets the lower port.
        def port_assignments(projects, base_port)
          projects.each_with_index.to_h { |project, index| [project.name, base_port + index] }
        end

        def serve(boot, ports, host)
          apps_by_port = build_apps(boot, ports)
          announce(ports, host)
          server_factory.call(apps_by_port, host: host).run
          SUCCESS
        rescue Interrupt
          out.puts STOP_MESSAGE
          SUCCESS
        end

        def build_apps(boot, ports)
          env_name = env.fetch(ENV_VARIABLE, DEFAULT_ENV)
          ports.to_h { |name, port| [port, boot.app(name, env_name: env_name)] }
        end

        def announce(ports, host)
          out.puts "Boto running (Ctrl-C to stop)"
          ports.each { |name, port| out.puts "  #{name}  http://#{host}:#{port}" }
        end
      end
    end
  end
end
