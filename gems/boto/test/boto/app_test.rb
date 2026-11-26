# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "json"

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
      assert_equal %w[AppTestShop::Boom AppTestShop::Search AppTestShop::Users::Create
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

    private

    def post_json(path, body)
      request_for.post(path, input: JSON.generate(body), "CONTENT_TYPE" => JSON_TYPE)
    end
  end
end
