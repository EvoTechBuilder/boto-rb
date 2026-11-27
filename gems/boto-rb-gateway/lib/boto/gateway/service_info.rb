# frozen_string_literal: true

module Boto
  module Gateway
    # What the panel shows of one service. Route paths have no prefix; the prefix is added to the links.
    ServiceInfo = Data.define(:name, :prefix, :port, :random_port, :health, :routes, :openapi, :swagger, :env)

    class ServiceInfo
      Route = Data.define(:verb, :path, :endpoint)

      OPENAPI_PATH = Boto::App::OPENAPI_PATH
      OPENAPI_PLUGIN = :openapi
      SWAGGER_PLUGIN = :swagger_ui

      # host: the panel request's host, so a service with :hosts accepts the probe as it accepts the panel.
      def self.build(name, prefix, app, solution_keys, host: nil)
        new(name: name, prefix: prefix, port: app.port, random_port: random_port?(app),
            health: Health.check(app, host: host), routes: routes_of(app),
            openapi: "#{prefix}#{openapi_path(app)}", swagger: swagger_link(app, prefix),
            env: EnvRows.project(app.env, solution_keys))
      end

      def self.random_port?(app)
        app.env&.source(EnvRows::PORT) == EnvRows::BOTO_RUN_SOURCE
      end

      def self.routes_of(app)
        app.endpoints.map do |endpoint|
          verb, path = endpoint.route
          Route.new(verb: verb, path: path, endpoint: endpoint.name)
        end
      end

      # The OpenAPI plugin keeps its own path; without it the core serves the default in development.
      def self.openapi_path(app)
        plugin = plugin_named(app, OPENAPI_PLUGIN)
        plugin ? plugin.path : OPENAPI_PATH
      end

      def self.swagger_link(app, prefix)
        plugin = plugin_named(app, SWAGGER_PLUGIN)
        "#{prefix}#{plugin.path}" if plugin
      end

      def self.plugin_named(app, name)
        app.plugins.find { |plugin| plugin.class.plugin_name == name }
      end

      def ready? = health.status == Health::READY

      def failing? = health.status == Health::FAILING
    end
  end
end
