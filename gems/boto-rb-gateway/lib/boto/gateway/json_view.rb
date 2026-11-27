# frozen_string_literal: true

require "json"

module Boto
  module Gateway
    # The panel's data as JSON, for /_boto/services.json. Same values as the HTML page.
    module JsonView
      module_function

      def render(page)
        JSON.generate(document(page))
      end

      def document(page)
        { gateway: page.gateway, env: page.env_name, solution_env: page.solution_env.map { |row| row_hash(row) },
          services: page.services.map { |service| service_hash(service, page) } }
      end

      def service_hash(service, page)
        { name: service.name, prefix: service.prefix, port: service.port,
          health: { status: service.health.status.to_s, detail: service.health.detail },
          routes: service.routes.map { |route| route_hash(route) },
          openapi: page.link(service.openapi), swagger: service.swagger && page.link(service.swagger),
          env: service.env.map { |row| row_hash(row) } }
      end

      def route_hash(route)
        { method: route.verb, path: route.path, endpoint: route.endpoint }
      end

      def row_hash(row)
        { name: row.name, value: row.value, source: row.source, masked: row.masked }
      end
    end
  end
end
