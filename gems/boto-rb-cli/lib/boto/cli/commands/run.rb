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
        DEFAULT_SHUTDOWN_TIMEOUT = 25
        DEFAULT_DRAIN_DELAY = 0
        STOP_MESSAGE = "Stopping"
        DRAIN_MESSAGE = "Stopping (draining up to %g s)"
        OPTIONS = [
          Option.new(key: :port, flags: %w[--port], argument: "N", type: Integer,
                     description: "First port; each service gets the next one (default #{DEFAULT_PORT})"),
          Option.new(key: :host, flags: %w[--host], argument: "H",
                     description: "Host to bind (default #{Boto::CLI::Server::DEFAULT_HOST})"),
          Option.new(key: :shutdown_timeout, flags: %w[--shutdown-timeout], argument: "N", type: Float,
                     description: "Seconds to wait for requests in flight on shutdown (default #{DEFAULT_SHUTDOWN_TIMEOUT})"),
          Option.new(key: :drain_delay, flags: %w[--drain-delay], argument: "N", type: Float,
                     description: "Seconds to keep serving after readiness turns 503 (default #{DEFAULT_DRAIN_DELAY})")
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
          serve(boot, ports, options)
        ensure
          # Releases the Zeitwerk loaders so the same solution can be booted again in this process.
          boot&.shutdown
        end

        private

        attr_reader :server_factory, :env

        def parse_options
          options = default_options
          positional = option_parser(options).parse(argv)
          raise Error, USAGE if positional.size > 1

          validate_options(options)
          options.merge(project: positional.first)
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def default_options
          { port: DEFAULT_PORT, host: Boto::CLI::Server::DEFAULT_HOST,
            shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT, drain_delay: DEFAULT_DRAIN_DELAY }
        end

        def validate_options(options)
          raise Error, %(invalid port "#{options[:port]}") unless VALID_PORTS.cover?(options[:port])
          unless options[:shutdown_timeout].positive?
            raise Error, %(invalid shutdown timeout "#{options[:shutdown_timeout]}")
          end
          raise Error, %(invalid drain delay "#{options[:drain_delay]}") if options[:drain_delay].negative?
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

        # Exit status 1 when a second signal cut the drain short, 0 otherwise. boot.shutdown still runs (ensure).
        def serve(boot, ports, options)
          apps_by_port = build_apps(boot, ports)
          announce(ports, options[:host])
          server = server_factory.call(apps_by_port, host: options[:host])
          signals = Boto::CLI::ShutdownSignal.new
          signals.install { server.run { drain_on_signal(server, signals, options) } }
          signals.repeated? ? FAILURE : SUCCESS
        rescue Interrupt
          out.puts STOP_MESSAGE
          SUCCESS
        end

        def drain_on_signal(server, signals, options)
          signals.wait
          out.puts format(DRAIN_MESSAGE, options[:shutdown_timeout])
          server.drain(delay: options[:drain_delay], timeout: options[:shutdown_timeout],
                       interrupted: -> { signals.repeated? })
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
