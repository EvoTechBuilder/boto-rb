# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "json"

# Stand-ins: the core must not depend on boto-rb-security, so :auth and :hosts are faked here.
module OpenAPIPluginFakes
  class Hosts < Boto::Plugin
    scope :global

    def call(_env, _app)
      Boto::Error::Forbidden.new("blocked").to_response
    end
  end

  class Bearer
    def security_scheme = { "type" => "http", "scheme" => "bearer" }
  end

  class Auth < Boto::Plugin
    # The document generator reads the security scheme from the strategy, as the real :auth does.
    def strategy = Bearer.new

    def call(env, app)
      return app.call(env) if env["HTTP_AUTHORIZATION"] == "Bearer good"

      [401, { "content-type" => "application/json" }, ["{}"]]
    end
  end

  module Shop
    class Show < Boto::Endpoint
      get "/users/:id"
      param :id, Integer
      def call(id:) = { id: }
    end
  end

  module Conflicting
    class Docs < Boto::Endpoint
      get "/openapi.json"
      def call = {}
    end
  end
end

module Boto
  module Plugins
    class OpenAPITest < Minitest::Test
      def plugin(**options)
        Boto::Plugins::OpenAPI.new(env_name: "production", **options)
      end

      def app(plugins: [plugin], namespace: OpenAPIPluginFakes::Shop, env_name: "production")
        Boto::App.new(namespace: namespace, plugins: plugins, env_name: env_name, error_output: StringIO.new).tap(&:start)
      end

      def get(application, path, headers = {})
        Rack::MockRequest.new(application).get(path, headers)
      end

      def document_for(application, version)
        JSON.generate(Boto::OpenAPI.generate(application, title: application.title, version: version))
      end

      def test_get_serves_the_default_path
        res = get(app, "/openapi.json")
        assert_equal 200, res.status
        assert_equal "application/json", res.content_type
      end

      def test_head_serves_the_default_path_without_body
        res = Rack::MockRequest.new(app).request("HEAD", "/openapi.json")
        assert_equal 200, res.status
        assert_equal "", res.body
      end

      def test_serves_a_custom_path
        application = app(plugins: [plugin(path: "/docs/openapi.json")])
        assert_equal 200, get(application, "/docs/openapi.json").status
        assert_equal 404, get(application, "/openapi.json").status
      end

      def test_responds_the_same_in_development
        production = get(app(env_name: "production"), "/openapi.json")
        development = get(app(env_name: "development"), "/openapi.json")
        assert_equal production.body, development.body
        assert_equal 200, development.status
      end

      def test_other_path_and_post_pass_through_to_the_app
        application = app
        assert_equal 404, get(application, "/other").status
        assert_equal 404, Rack::MockRequest.new(application).post("/openapi.json").status
      end

      def test_body_is_the_generated_document_with_the_given_version
        application = app(plugins: [plugin(version: "0.10.0")])
        assert_equal document_for(application, "0.10.0"), get(application, "/openapi.json").body
      end

      def test_title_and_description_are_in_the_served_info
        application = app(plugins: [plugin(title: "Pedidos API", description: "Pedidos, pagamentos e entregas.", version: "1.4.0")])
        info = JSON.parse(get(application, "/openapi.json").body)["info"]
        assert_equal({ "title" => "Pedidos API", "description" => "Pedidos, pagamentos e entregas.", "version" => "1.4.0" }, info)
      end

      def test_default_title_is_the_namespace_and_info_has_no_description
        info = JSON.parse(get(app, "/openapi.json").body)["info"]
        assert_equal({ "title" => "OpenAPIPluginFakes::Shop", "version" => "0.0.0" }, info)
      end

      def test_title_method_is_the_configured_title_after_attach
        openapi = plugin(title: "Pedidos API")
        app(plugins: [openapi])
        assert_equal "Pedidos API", openapi.title
      end

      def test_title_method_falls_back_to_the_namespace_after_attach
        openapi = plugin
        app(plugins: [openapi])
        assert_equal "OpenAPIPluginFakes::Shop", openapi.title
      end

      def test_title_must_be_a_non_blank_string_or_nil
        ["", "  ", 1].each do |title|
          error = assert_raises(ArgumentError) { plugin(title: title) }
          assert_match(/\Aopenapi: title must be/, error.message)
        end
      end

      def test_description_must_be_a_string_or_nil
        error = assert_raises(ArgumentError) { plugin(description: 1) }
        assert_match(/\Aopenapi: description must be/, error.message)
      end

      def test_every_response_hands_out_the_same_string
        application = app
        first = application.call(Rack::MockRequest.env_for("/openapi.json"))
        second = application.call(Rack::MockRequest.env_for("/openapi.json"))
        assert_same first[2].first, second[2].first
        assert_predicate first[2].first, :frozen?
      end

      def test_auth_without_token_is_unauthorized
        assert_equal 401, get(app(plugins: [plugin, OpenAPIPluginFakes::Auth.new(env_name: "production")]), "/openapi.json").status
      end

      def test_auth_with_wrong_token_is_unauthorized
        application = app(plugins: [plugin, OpenAPIPluginFakes::Auth.new(env_name: "production")])
        assert_equal 401, get(application, "/openapi.json", "HTTP_AUTHORIZATION" => "Bearer bad").status
      end

      def test_auth_with_right_token_is_served
        application = app(plugins: [plugin, OpenAPIPluginFakes::Auth.new(env_name: "production")])
        assert_equal 200, get(application, "/openapi.json", "HTTP_AUTHORIZATION" => "Bearer good").status
      end

      def test_auth_false_is_served_without_token
        application = app(plugins: [plugin(auth: false), OpenAPIPluginFakes::Auth.new(env_name: "production")])
        assert_equal 200, get(application, "/openapi.json").status
      end

      def test_guard_is_the_auth_plugin_that_protects_the_document
        openapi = plugin
        auth = OpenAPIPluginFakes::Auth.new(env_name: "production")
        app(plugins: [openapi, auth])
        assert_same auth, openapi.guard
      end

      def test_guard_is_nil_when_the_document_is_not_authenticated
        openapi = plugin(auth: false)
        app(plugins: [openapi, OpenAPIPluginFakes::Auth.new(env_name: "production")])
        assert_nil openapi.guard
      end

      def test_no_auth_plugin_in_project_is_served
        assert_equal 200, get(app, "/openapi.json").status
      end

      def test_path_without_leading_slash_is_rejected
        error = assert_raises(ArgumentError) { plugin(path: "openapi.json") }
        assert_match(/^openapi: /, error.message)
      end

      def test_version_must_be_a_string
        error = assert_raises(ArgumentError) { plugin(version: 1) }
        assert_match(/^openapi: /, error.message)
      end

      def test_auth_must_be_boolean
        error = assert_raises(ArgumentError) { plugin(auth: "yes") }
        assert_match(/^openapi: /, error.message)
      end

      def test_endpoint_on_the_same_path_fails_at_boot
        error = assert_raises(ArgumentError) { app(namespace: OpenAPIPluginFakes::Conflicting) }
        assert_match(/Conflicting::Docs/, error.message)
      end

      def test_without_the_plugin_development_still_serves_the_document
        assert_equal 200, get(app(plugins: [], env_name: "development"), "/openapi.json").status
      end

      def test_with_the_plugin_on_a_custom_path_development_does_not_serve_the_default
        application = app(plugins: [plugin(path: "/docs/openapi.json")], env_name: "development")
        assert_equal 404, get(application, "/openapi.json").status
      end

      def test_global_hosts_plugin_answers_before_the_document
        application = app(plugins: [OpenAPIPluginFakes::Hosts.new(env_name: "production"), plugin])
        assert_equal 403, get(application, "/openapi.json").status
      end

      def test_script_name_adds_servers_with_the_prefix_and_keeps_paths
        application = app
        document = JSON.parse(get(application, "/openapi.json", "SCRIPT_NAME" => "/catalogo").body)
        assert_equal [{ "url" => "/catalogo" }], document["servers"]
        assert_equal JSON.parse(get(application, "/openapi.json").body)["paths"], document["paths"]
      end

      def test_empty_script_name_is_the_same_as_none
        assert_equal get(app, "/openapi.json").body, get(app, "/openapi.json", "SCRIPT_NAME" => "").body
      end

      def test_script_name_with_custom_path_adds_servers
        application = app(plugins: [plugin(path: "/docs/openapi.json")])
        document = JSON.parse(get(application, "/docs/openapi.json", "SCRIPT_NAME" => "/catalogo").body)
        assert_equal [{ "url" => "/catalogo" }], document["servers"]
      end

      def test_same_script_name_hands_out_the_same_string
        application = app
        first = application.call(Rack::MockRequest.env_for("/openapi.json", "SCRIPT_NAME" => "/catalogo"))
        second = application.call(Rack::MockRequest.env_for("/openapi.json", "SCRIPT_NAME" => "/catalogo"))
        assert_same first[2].first, second[2].first
      end

      def test_order_puts_openapi_and_swagger_ui_between_csrf_and_auth
        order = Boto::Plugin::ORDER
        assert order.index(:csrf) < order.index(:openapi)
        assert order.index(:openapi) < order.index(:swagger_ui)
        assert order.index(:swagger_ui) < order.index(:auth)
      end
    end
  end
end
