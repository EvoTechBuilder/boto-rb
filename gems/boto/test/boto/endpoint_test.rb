# frozen_string_literal: true

require "test_helper"
require "rack/mock"

module Boto
  class EndpointTest < Minitest::Test
    def test_each_verb_defines_its_route
      assert_equal ["GET", "/x"], Class.new(Boto::Endpoint) { get "/x" }.route
      assert_equal ["POST", "/x"], Class.new(Boto::Endpoint) { post "/x" }.route
      assert_equal ["PUT", "/x"], Class.new(Boto::Endpoint) { put "/x" }.route
      assert_equal ["PATCH", "/x"], Class.new(Boto::Endpoint) { patch "/x" }.route
      assert_equal ["DELETE", "/x"], Class.new(Boto::Endpoint) { delete "/x" }.route
    end

    def test_route_is_nil_without_declaration
      assert_nil Class.new(Boto::Endpoint).route
    end

    def test_second_route_raises_route_error
      error = assert_raises(Boto::Endpoint::RouteError) do
        Class.new(Boto::Endpoint) do
          get "/x"
          post "/y"
        end
      end
      assert_equal "route already defined: GET /x", error.message
    end

    def test_path_without_leading_slash_raises_argument_error
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { get "x" } }
    end

    def test_path_param_names_lists_dynamic_segments
      endpoint = Class.new(Boto::Endpoint) { get "/users/:id/posts/:post_id" }
      assert_equal %i[id post_id], endpoint.path_param_names
    end

    def test_path_param_names_is_empty_for_static_path_or_no_route
      assert_equal [], Class.new(Boto::Endpoint) { get "/users" }.path_param_names
      assert_equal [], Class.new(Boto::Endpoint).path_param_names
    end

    def test_param_declares_in_params
      endpoint = Class.new(Boto::Endpoint) do
        get "/x"
        param :id, Integer
        param :name, String
      end
      assert_equal %i[id name], endpoint.params.names
    end

    def test_params_are_not_shared_between_subclasses
      first = Class.new(Boto::Endpoint) { param :a, Integer }
      second = Class.new(Boto::Endpoint) { param :b, String }
      assert_equal %i[a], first.params.names
      assert_equal %i[b], second.params.names
    end

    def test_default_status_is_200
      assert_equal 200, Class.new(Boto::Endpoint).default_status
    end

    def test_declared_status_is_used
      endpoint = Class.new(Boto::Endpoint) { status 201 }
      assert_equal 201, endpoint.default_status
    end

    def test_invalid_status_raises_argument_error
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { status 99 } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { status "200" } }
    end

    def test_compile_freezes_params_and_returns_class
      endpoint = Class.new(Boto::Endpoint) { param :id, Integer }
      assert_same endpoint, endpoint.compile!
      assert_predicate endpoint.params, :frozen?
    end

    def test_call_returns_value_from_keyword_args
      endpoint = Class.new(Boto::Endpoint) do
        get "/users/:id"
        def call(id:) = { id: id }
      end
      assert_equal({ id: 1 }, endpoint.new.call(id: 1))
    end

    def test_not_found_raises_not_found
      error = assert_raises(Boto::Error::NotFound) { Class.new(Boto::Endpoint) { def call = not_found("gone") }.new.call }
      assert_equal "gone", error.detail
    end

    def test_bad_request_raises_bad_request
      assert_raises(Boto::Error::BadRequest) { Class.new(Boto::Endpoint) { def call = bad_request }.new.call }
    end

    def test_unprocessable_raises_with_errors
      errors = [{ param: "id", message: "is required" }]
      endpoint = Class.new(Boto::Endpoint) { def call(errors:) = unprocessable(errors) }
      error = assert_raises(Boto::Error::Unprocessable) { endpoint.new.call(errors: errors) }
      assert_equal errors, error.errors
    end

    def test_call_without_implementation_raises
      endpoint = Class.new(Boto::Endpoint)
      error = assert_raises(NotImplementedError) { endpoint.new.call }
      assert_equal "#{endpoint} must implement #call", error.message
    end

    def test_request_wraps_env
      env = Rack::MockRequest.env_for("/x?a=1")
      request = Class.new(Boto::Endpoint) { get "/x" }.new(env).request
      assert_instance_of Rack::Request, request
      assert_equal "1", request.GET["a"]
    end
  end
end
