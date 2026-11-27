# frozen_string_literal: true

require "boto/gateway"

# Real Boto::App instances for the panel tests: two services and a gateway that mounts them.
module PanelFakes
  module Gateway
  end

  module Catalogo
    class ListProducts < Boto::Endpoint
      get "/products"
      def call = []
    end

    class CreateProduct < Boto::Endpoint
      post "/products"
      def call = {}
    end
  end

  module Pedidos
    class CreateOrder < Boto::Endpoint
      post "/orders"
      def call = {}
    end
  end

  # Stands in for the swagger plugin: its name makes the panel show a Swagger link.
  class SwaggerUi < Boto::Plugin
    scope :global

    def path = "/docs"
  end

  module_function

  def gateway_env
    Boto::Env.new({ "BOTO_ENV" => "development", "REDIS_URL" => "redis://localhost:6379/0",
                    "SENTRY_DSN" => "https://key@sentry.example/1" },
                  sources: { "BOTO_ENV" => "process", "REDIS_URL" => ".env", "SENTRY_DSN" => ".env.local" },
                  file_keys: %w[REDIS_URL SENTRY_DSN])
  end

  def catalogo_env
    Boto::Env.new({ "PORT" => "4101", "DATABASE_URL" => "postgres://catalogo:s3cret@localhost/catalogo_dev",
                    "NOTE" => "<script>alert(1)</script>" },
                  sources: { "PORT" => ".env", "DATABASE_URL" => "apps/catalogo/.env.development",
                             "NOTE" => "apps/catalogo/.env" },
                  file_keys: %w[PORT DATABASE_URL NOTE])
  end

  def pedidos_env
    Boto::Env.new({ "PORT" => "61042", "PAYMENT_API_KEY" => "k_live_123" },
                  sources: { "PORT" => "boto run", "PAYMENT_API_KEY" => ".env.local" },
                  file_keys: %w[PAYMENT_API_KEY])
  end

  def health(checks: {})
    Boto::Plugins::Health.new(env_name: "development", checks: checks)
  end

  def catalogo_app(checks: {}, port: 4101)
    started(Boto::App.new(namespace: Catalogo, plugins: [health(checks: checks)], env_name: "development",
                          port: port, env: catalogo_env))
  end

  def pedidos_app(port: nil, env: pedidos_env)
    started(Boto::App.new(namespace: Pedidos, env_name: "development", port: port, env: env))
  end

  def started(app)
    app.start
    app
  end

  def gateway_app(services:, plugins: [Boto::Plugins::Gateway.new(env_name: "development")])
    started(Boto::App.new(namespace: Gateway, plugins: plugins, env_name: "development", env: gateway_env,
                          services: services))
  end

  def default_services
    { "catalogo" => catalogo_app, "pedidos" => pedidos_app }
  end

  def page(services: default_services, base: "")
    gateway = gateway_app(services: services, plugins: [])
    Boto::Gateway::Page.build(gateway_app: gateway, mounts: Boto::Gateway::Mounts.new(services: services),
                              env_name: "development", host: "localhost:3000", base: base)
  end
end
