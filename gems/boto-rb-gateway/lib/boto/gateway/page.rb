# frozen_string_literal: true

module Boto
  module Gateway
    # Everything the panel shows, built on each request so the health checks run at page load.
    # base is the SCRIPT_NAME of the request, so links work behind a mount point.
    Page = Data.define(:gateway, :env_name, :host, :base, :solution_env, :services) do
      def self.build(gateway_app:, mounts:, env_name:, host:, base:)
        solution_keys = EnvRows.solution_keys(gateway_app.env)
        new(gateway: gateway_app.title, env_name: env_name, host: host, base: base,
            solution_env: EnvRows.solution(gateway_app.env),
            services: mounts.entries.map { |name, prefix, app| ServiceInfo.build(name, prefix, app, solution_keys, host: host) })
      end

      def link(path) = "#{base}#{path}"

      def ready_count = services.count(&:ready?)

      def failing_count = services.count(&:failing?)

      def route_count = services.sum { |service| service.routes.size }
    end
  end
end
