# frozen_string_literal: true

require "test_helper"
require "boto/security"
require "rack/mock"
require "stringio"

# Endpoints for each namespace the tests boot. Pass-through checks need a real route to reach.
module SwaggerUiFakes
  module Shop
    class Show < Boto::Endpoint
      get "/users/:id"
      param :id, Integer
      def call(id:) = { id: }
    end
  end

  module Conflicting
    class Docs < Boto::Endpoint
      get "/docs"
      def call = {}
    end
  end

  module Passing
    class Docsx < Boto::Endpoint
      get "/docsx"
      def call = { ok: true }
    end

    class Create < Boto::Endpoint
      post "/docs"
      def call = { ok: true }
    end
  end
end

module Boto
  module Plugins
    class SwaggerUiTest < Minitest::Test
      CSS = "text/css; charset=utf-8"
      JS = "text/javascript; charset=utf-8"
      HTML = "text/html; charset=utf-8"
      IMMUTABLE = "public, max-age=31536000, immutable"
      NO_CACHE = "no-cache"
      ASSETS_VERSION = "#{Boto::SwaggerUi::Assets.load.version}-#{Boto::SwaggerUi::VERSION}"
      ASSET_HEADERS = {
        "swagger-ui.css" => [CSS, IMMUTABLE],
        "swagger-ui-bundle.js" => [JS, IMMUTABLE],
        "initializer.js" => [JS, NO_CACHE]
      }.freeze
      BASIC_AUTH = { "HTTP_AUTHORIZATION" => "Basic #{["admin:secret"].pack("m0")}" }.freeze

      def swagger(**options)
        Boto::Plugins::SwaggerUi.new(env_name: "production", **options)
      end

      def openapi(**options)
        Boto::Plugins::OpenAPI.new(env_name: "production", **options)
      end

      def basic_auth
        Boto::Plugins::Auth.new(env_name: "production", strategy: :basic, credentials: { "admin" => "secret" })
      end

      def app(plugins: [openapi, swagger], namespace: SwaggerUiFakes::Shop, env_name: "production")
        Boto::App.new(namespace: namespace, plugins: plugins, env_name: env_name, error_output: StringIO.new).tap(&:start)
      end

      def get(application, path, headers = {})
        Rack::MockRequest.new(application).get(path, headers)
      end

      def asset_url(name, base: "/docs")
        "#{base}/assets/#{ASSETS_VERSION}/#{name}"
      end

      def test_get_serves_the_page
        res = get(app, "/docs")
        assert_equal 200, res.status
        assert_equal HTML, res.content_type
        assert_equal NO_CACHE, res.headers["cache-control"]
        assert_includes res.body, "swagger-ui-bundle.js"
      end

      def test_head_serves_the_page_without_body
        res = Rack::MockRequest.new(app).request("HEAD", "/docs")
        assert_equal 200, res.status
        assert_equal HTML, res.content_type
        assert_equal "", res.body
      end

      def test_get_and_head_serve_each_asset_with_its_headers
        application = app
        ASSET_HEADERS.each do |name, (type, cache)|
          res = get(application, asset_url(name))
          assert_equal 200, res.status, name
          assert_equal type, res.content_type, name
          assert_equal cache, res.headers["cache-control"], name

          head = Rack::MockRequest.new(application).request("HEAD", asset_url(name))
          assert_equal 200, head.status, name
          assert_equal "", head.body, name
        end
      end

      def test_serves_under_a_custom_path
        application = app(plugins: [openapi, swagger(path: "/api-docs")])
        assert_equal 200, get(application, "/api-docs").status
        assert_equal 200, get(application, asset_url("swagger-ui.css", base: "/api-docs")).status
        assert_equal 404, get(application, "/docs").status
      end

      def test_unknown_asset_is_not_found
        assert_equal 404, get(app, asset_url("nope.js")).status
      end

      def test_path_traversal_out_of_assets_is_not_found
        assert_equal 404, get(app, "/docs/assets/#{ASSETS_VERSION}/../VERSION").status
      end

      def test_other_paths_and_post_pass_through_to_the_app
        application = app
        assert_equal 404, get(application, "/other").status
        assert_equal 404, Rack::MockRequest.new(application).post("/docs").status
      end

      def test_prefix_neighbours_and_post_reach_the_endpoints
        application = app(namespace: SwaggerUiFakes::Passing)
        assert_equal 200, get(application, "/docsx").status
        res = Rack::MockRequest.new(application).post("/docs")
        assert_includes res.body, "ok"
      end

      def test_page_points_at_the_openapi_path
        application = app(plugins: [openapi(path: "/spec.json"), swagger])
        assert_includes get(application, asset_url("initializer.js")).body, '"/spec.json"'
      end

      def test_page_title_comes_from_the_openapi_title
        application = app(plugins: [openapi(title: "Pedidos API"), swagger])
        assert_includes get(application, "/docs").body, "<title>Pedidos API</title>"
      end

      def test_page_title_defaults_to_the_namespace
        assert_includes get(app, "/docs").body, "<title>SwaggerUiFakes::Shop</title>"
      end

      def test_asset_urls_carry_the_swagger_ui_and_gem_versions
        assert_includes get(app, "/docs").body, "/docs/assets/5.36.0-#{Boto::SwaggerUi::VERSION}/boto.css"
      end

      def test_brand_assets_are_served_immutable
        application = app
        { "boto.css" => "text/css; charset=utf-8", "ruby.svg" => "image/svg+xml",
          "swagger-ui-standalone-preset.js" => "text/javascript; charset=utf-8" }.each do |name, type|
          response = get(application, asset_url(name))
          assert_equal [200, type], [response.status, response.content_type], name
          assert_includes response.headers["cache-control"], "immutable", name
        end
      end

      def test_asset_bodies_are_built_once
        application = app
        path = asset_url("swagger-ui.css")
        first = application.call(Rack::MockRequest.env_for(path))[2].first
        second = application.call(Rack::MockRequest.env_for(path))[2].first
        assert_same first, second
        assert_predicate first, :frozen?
      end

      def test_basic_auth_without_credentials_is_unauthorized
        application = app(plugins: [openapi, basic_auth, swagger])
        assert_equal 401, get(application, "/docs").status
        assert_equal 401, get(application, asset_url("swagger-ui.css")).status
      end

      def test_basic_auth_with_credentials_is_served
        application = app(plugins: [openapi, basic_auth, swagger])
        assert_equal 200, get(application, "/docs", BASIC_AUTH).status
        assert_equal 200, get(application, asset_url("swagger-ui.css"), BASIC_AUTH).status
      end

      def test_document_without_auth_keeps_the_page_open
        application = app(plugins: [openapi(auth: false), basic_auth, swagger])
        assert_equal 200, get(application, "/docs").status
      end

      def test_without_openapi_fails_at_boot
        error = assert_raises(ArgumentError) { app(plugins: [swagger]) }
        assert_match(/needs app\.use :openapi/, error.message)
      end

      def test_bearer_document_fails_at_boot_with_a_suggestion
        bearer = Boto::Plugins::Auth.new(env_name: "production", strategy: :bearer, tokens: ["good"])
        error = assert_raises(ArgumentError) { app(plugins: [openapi, bearer, swagger]) }
        assert_match(/auth: false/, error.message)
        assert_match(/strategy: :basic/, error.message)
      end

      def test_invalid_path_fails_at_boot
        ["docs", "/docs/", "/"].each do |path|
          error = assert_raises(ArgumentError) { swagger(path: path) }
          assert_match(/^swagger_ui: /, error.message, path)
        end
      end

      def test_endpoint_on_the_same_path_fails_at_boot
        error = assert_raises(ArgumentError) { app(namespace: SwaggerUiFakes::Conflicting) }
        assert_match(/Conflicting::Docs/, error.message)
      end

      def test_name_resolves_to_the_plugin
        plugin = Boto::Configuration.new(env_name: "production").use(:swagger_ui).plugin(:swagger_ui)
        assert_instance_of Boto::Plugins::SwaggerUi, plugin
      end
    end
  end
end
