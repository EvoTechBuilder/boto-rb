# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "json"

module AppTestQuery
  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  class SearchSchema < Boto::Schema
    field :name, String, min: 1
  end

  class Search < Boto::Endpoint
    query "/users/search"
    body SearchSchema
    returns [UserSchema]
    def call(body:) = [{ id: 1, name: body.name }]
  end

  module Items
    class Index < Boto::Endpoint
      get "/items"
      def call = { source: "get" }
    end

    class Lookup < Boto::Endpoint
      query "/items"
      def call = { source: "query" }
    end
  end
end

module AppTestShop
  module Users
    class Show < Boto::Endpoint
      get "/users/:id"
      param :id, Integer
      def call(id:) = id == 404 ? not_found : { id: }
    end

    class Create < Boto::Endpoint
      post "/users"
      status 201
      param :name, String
      param :admin, Boto::Boolean, default: false
      def call(name:, admin:) = { name:, admin: }
    end

    class Destroy < Boto::Endpoint
      delete "/users/:id"
      param :id, Integer
      def call(id:) = nil
    end
  end

  class Boom < Boto::Endpoint
    get "/boom"
    def call = raise("kaboom")
  end

  class Todo < Boto::Endpoint
    get "/todo"
    def call = raise(NotImplementedError, "AppTestShop::Todo#call")
  end

  class Search < Boto::Endpoint
    get "/search"
    param :q, String
    param :page, Integer, default: 1
    def call(q:, page:) = { q:, page: }
  end
end

module AppTestUndeclared
  class Item < Boto::Endpoint
    get "/items/:id"
    def call(id:) = { id: }
  end
end

module AppTestDuplicate
  class First < Boto::Endpoint
    get "/same"
    def call = {}
  end

  class Second < Boto::Endpoint
    get "/same"
    def call = {}
  end
end

module AppTestSchemas
  class AddressSchema < Boto::Schema
    field :zip, String, pattern: /\A\d{5}\z/
  end

  class UserInputSchema < Boto::Schema
    field :name, String, min: 1
    field :address, AddressSchema, required: false
  end

  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  User = Struct.new(:id, :name, :password_hash)

  module Users
    class Create < Boto::Endpoint
      post "/users"
      status 201
      body AppTestSchemas::UserInputSchema
      returns AppTestSchemas::UserSchema
      param :notify, Boto::Boolean, default: false
      def call(body:, notify:) = AppTestSchemas::User.new(1, body.name, "secret")
    end

    class Index < Boto::Endpoint
      get "/users"
      returns [AppTestSchemas::UserSchema]
      def call = [AppTestSchemas::User.new(1, "Ana", "x"), { id: 2, name: "Bia" }]
    end

    class Broken < Boto::Endpoint
      get "/broken"
      returns AppTestSchemas::UserSchema
      def call = { id: 1 }
    end
  end
end

module AppTestBodyConflict
  class Create < Boto::Endpoint
    post "/conflict"
    body AppTestSchemas::UserInputSchema
    param :body, String
    def call(body:) = nil
  end
end

module AppTestCustomDoc
  class Doc < Boto::Endpoint
    get "/openapi.json"
    def call = { custom: true }
  end
end

module Boto
  class AppTest < Minitest::Test
    JSON_TYPE = "application/json"
    PROBLEM_TYPE = "application/problem+json"

    def setup
      @error_output = StringIO.new
    end

    def app(namespace: AppTestShop, env_name: "production")
      Boto::App.new(namespace: namespace, env_name: env_name, error_output: @error_output)
    end

    def request_for(namespace: AppTestShop, env_name: "production")
      Rack::MockRequest.new(app(namespace: namespace, env_name: env_name))
    end

    def json(body)
      JSON.parse(body)
    end

    def test_discovers_endpoints_in_namespace
      names = app.endpoints.map(&:name)
      assert_equal %w[AppTestShop::Boom AppTestShop::Search AppTestShop::Todo AppTestShop::Users::Create
                      AppTestShop::Users::Destroy AppTestShop::Users::Show], names
    end

    def test_get_with_path_param_returns_json
      res = request_for.get("/users/7")
      assert_equal 200, res.status
      assert_equal JSON_TYPE, res.headers["content-type"]
      assert_equal({ "id" => 7 }, json(res.body))
    end

    def test_error_from_endpoint_returns_problem_json
      res = request_for.get("/users/404")
      assert_equal 404, res.status
      assert_equal PROBLEM_TYPE, res.headers["content-type"]
    end

    def test_invalid_path_param_returns_422_with_errors
      res = request_for.get("/users/abc")
      assert_equal 422, res.status
      assert_equal [{ "param" => "id", "message" => "must be an Integer" }], json(res.body)["errors"]
    end

    def test_post_with_json_body_returns_created
      res = post_json("/users", { name: "Ana" })
      assert_equal 201, res.status
      assert_equal({ "name" => "Ana", "admin" => false }, json(res.body))
    end

    def test_post_without_required_param_returns_422
      res = post_json("/users", {})
      assert_equal 422, res.status
      assert_equal [{ "param" => "name", "message" => "is required" }], json(res.body)["errors"]
    end

    def test_post_with_invalid_json_returns_400
      res = request_for.post("/users", input: "{", "CONTENT_TYPE" => JSON_TYPE)
      assert_equal 400, res.status
    end

    def test_query_params_are_parsed_and_undeclared_ones_ignored
      res = request_for.get("/search?q=x&page=2&other=1")
      assert_equal({ "q" => "x", "page" => 2 }, json(res.body))
    end

    def test_default_applies_when_query_param_is_missing
      res = request_for.get("/search?q=x")
      assert_equal({ "q" => "x", "page" => 1 }, json(res.body))
    end

    def test_nil_result_returns_no_content_with_empty_body
      res = request_for.delete("/users/1")
      assert_equal 204, res.status
      assert_equal "", res.body
    end

    def test_unknown_path_returns_404
      res = request_for.get("/nope")
      assert_equal 404, res.status
      assert_equal PROBLEM_TYPE, res.headers["content-type"]
    end

    def test_wrong_verb_returns_405_with_allow_header
      res = request_for.put("/users/1")
      assert_equal 405, res.status
      assert_equal "DELETE, GET, HEAD", res.headers["allow"]
    end

    def test_head_returns_status_and_headers_with_empty_body
      res = request_for.request("HEAD", "/users/7")
      assert_equal 200, res.status
      assert_equal JSON_TYPE, res.headers["content-type"]
      assert_equal "", res.body
    end

    def test_unexpected_error_in_production_hides_message
      res = request_for.get("/boom")
      assert_equal 500, res.status
      refute_includes res.body, "kaboom"
      assert_includes @error_output.string, "RuntimeError: kaboom"
    end

    # NotImplementedError is a ScriptError, not a StandardError; a generated endpoint still raises it.
    def test_not_implemented_endpoint_is_500_not_a_crash
      res = request_for(env_name: "development").get("/todo")
      assert_equal 500, res.status
      assert_includes res.body, "NotImplementedError: AppTestShop::Todo#call"
    end

    def test_unexpected_error_in_development_shows_message
      res = request_for(env_name: "development").get("/boom")
      assert_equal 500, res.status
      assert_includes res.body, "kaboom"
    end

    def test_head_on_error_has_empty_body
      res = request_for.request("HEAD", "/boom")
      assert_equal 500, res.status
      assert_equal "", res.body
    end

    def test_path_param_not_declared_raises_boot_error
      error = assert_raises(Boto::App::BootError) { app(namespace: AppTestUndeclared) }
      assert_includes error.message, ":id"
    end

    def test_duplicate_route_raises_boot_error
      error = assert_raises(Boto::App::BootError) { app(namespace: AppTestDuplicate) }
      assert_includes error.message, "AppTestDuplicate::Second"
    end

    def test_body_with_param_body_raises_boot_error
      error = assert_raises(Boto::App::BootError) { app(namespace: AppTestBodyConflict) }
      assert_includes error.message, "AppTestBodyConflict::Create"
      assert_includes error.message, "param :body conflicts"
    end

    def test_app_title_is_namespace_name
      assert_equal "AppTestSchemas", app(namespace: AppTestSchemas).title
      assert_predicate app(namespace: AppTestSchemas).title, :frozen?
    end

    def test_body_is_coerced_and_returned_serialized_without_hidden_fields
      res = post_json("/users", { name: "Ana" }, namespace: AppTestSchemas)
      assert_equal 201, res.status
      assert_equal({ "id" => 1, "name" => "Ana" }, json(res.body))
      refute_includes res.body, "password_hash"
      refute_includes res.body, "secret"
    end

    def test_invalid_body_returns_422_with_paths
      res = post_json("/users", { name: "", address: { zip: "x" } }, namespace: AppTestSchemas)
      assert_equal 422, res.status
      params = json(res.body)["errors"].map { |error| error["param"] }
      assert_equal %w[name address.zip], params
    end

    def test_malformed_body_returns_400
      res = request_for(namespace: AppTestSchemas).post("/users", input: "{", "CONTENT_TYPE" => JSON_TYPE)
      assert_equal 400, res.status
    end

    def test_empty_object_body_returns_required_error
      res = post_json("/users", {}, namespace: AppTestSchemas)
      assert_equal 422, res.status
      assert_equal [{ "param" => "name", "message" => "is required" }], json(res.body)["errors"]
    end

    def test_query_param_works_alongside_body
      res = request_for(namespace: AppTestSchemas).post(
        "/users?notify=true", input: JSON.generate({ name: "Ana" }), "CONTENT_TYPE" => JSON_TYPE
      )
      assert_equal 201, res.status
      assert_equal({ "id" => 1, "name" => "Ana" }, json(res.body))
    end

    def test_list_return_serializes_each_item
      res = request_for(namespace: AppTestSchemas).get("/users")
      assert_equal 200, res.status
      assert_equal [{ "id" => 1, "name" => "Ana" }, { "id" => 2, "name" => "Bia" }], json(res.body)
      refute_includes res.body, "password_hash"
    end

    def test_return_missing_required_field_is_500_and_logged
      res = request_for(namespace: AppTestSchemas).get("/broken")
      assert_equal 500, res.status
      refute_includes res.body, "OutputError"
      assert_includes @error_output.string, "OutputError"
    end

    def test_development_serves_openapi_document
      res = request_for(env_name: "development").get("/openapi.json")
      assert_equal 200, res.status
      assert_equal JSON_TYPE, res.headers["content-type"]
      document = json(res.body)
      assert_equal "3.1.0", document["openapi"]
      assert_includes document["paths"].keys, "/users/{id}"
    end

    def test_development_head_openapi_has_empty_body
      res = request_for(env_name: "development").request("HEAD", "/openapi.json")
      assert_equal 200, res.status
      assert_equal JSON_TYPE, res.headers["content-type"]
      assert_equal "", res.body
    end

    # Not a route, so it falls through to the normal unmatched handling.
    def test_development_post_openapi_is_404
      res = request_for(env_name: "development").post("/openapi.json")
      assert_equal 404, res.status
      assert_equal PROBLEM_TYPE, res.headers["content-type"]
    end

    def test_production_openapi_is_404
      res = request_for(env_name: "production").get("/openapi.json")
      assert_equal 404, res.status
      assert_equal PROBLEM_TYPE, res.headers["content-type"]
    end

    def test_user_endpoint_on_openapi_path_wins_over_generated_document
      res = request_for(namespace: AppTestCustomDoc, env_name: "development").get("/openapi.json")
      assert_equal 200, res.status
      assert_equal({ "custom" => true }, json(res.body))
    end

    def test_openapi_document_is_generated_once
      application = app(env_name: "development")
      env = Rack::MockRequest.env_for("/openapi.json")
      first_body = application.call(env)[2]
      second_body = application.call(env)[2]
      assert_same first_body[0], second_body[0]
    end

    def test_query_with_json_body_returns_serialized_list
      res = query_json("/users/search", { name: "ana" })
      assert_equal 200, res.status
      assert_equal [{ "id" => 1, "name" => "ana" }], json(res.body)
    end

    def test_query_with_invalid_body_returns_422_with_name_param
      res = query_json("/users/search", { name: "" })
      assert_equal 422, res.status
      assert_equal "name", json(res.body)["errors"].first["param"]
    end

    def test_head_on_query_only_path_returns_405_listing_query
      res = request_for(namespace: AppTestQuery).request("HEAD", "/users/search")
      assert_equal 405, res.status
      allowed = res.headers["allow"].split(", ")
      assert_includes allowed, "QUERY"
      refute_includes allowed, "HEAD"
    end

    def test_get_and_query_on_same_path_dispatch_to_their_own_endpoint
      get_res = request_for(namespace: AppTestQuery).get("/items")
      query_res = request_for(namespace: AppTestQuery).request("QUERY", "/items", input: "", "CONTENT_TYPE" => JSON_TYPE)
      assert_equal({ "source" => "get" }, json(get_res.body))
      assert_equal({ "source" => "query" }, json(query_res.body))
    end

    private

    def query_json(path, body, namespace: AppTestQuery)
      request_for(namespace: namespace).request("QUERY", path, input: JSON.generate(body), "CONTENT_TYPE" => JSON_TYPE)
    end

    def post_json(path, body, namespace: AppTestShop)
      request_for(namespace: namespace).post(path, input: JSON.generate(body), "CONTENT_TYPE" => JSON_TYPE)
    end

    def test_services_are_empty_and_frozen_by_default
      assert_empty app.services
      assert_predicate app.services, :frozen?
    end

    def test_services_are_kept_as_a_frozen_copy
      services = { "catalogo" => app }
      gateway = Boto::App.new(namespace: AppTestShop, error_output: @error_output, services: services)

      assert_equal services, gateway.services
      assert_predicate gateway.services, :frozen?
      refute_same services, gateway.services
    end

    def test_port_and_env_are_nil_by_default
      assert_nil app.port
      assert_nil app.env
    end

    def test_port_and_env_are_the_ones_given
      env = Boto::Env.new({ "PORT" => "4101" })
      built = Boto::App.new(namespace: AppTestShop, error_output: @error_output, port: 4101, env: env)

      assert_equal 4101, built.port
      assert_same env, built.env
    end
  end
end
