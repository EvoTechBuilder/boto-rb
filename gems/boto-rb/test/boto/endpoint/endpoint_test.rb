# frozen_string_literal: true

require "test_helper"
require "rack/mock"

module EndpointTestSchemas
  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  class PostSchema < Boto::Schema
    field :title, String
  end
end

module Boto
  class EndpointTest < Minitest::Test
    def test_each_verb_defines_its_route
      assert_equal ["GET", "/x"], Class.new(Boto::Endpoint) { get "/x" }.route
      assert_equal ["POST", "/x"], Class.new(Boto::Endpoint) { post "/x" }.route
      assert_equal ["PUT", "/x"], Class.new(Boto::Endpoint) { put "/x" }.route
      assert_equal ["PATCH", "/x"], Class.new(Boto::Endpoint) { patch "/x" }.route
      assert_equal ["DELETE", "/x"], Class.new(Boto::Endpoint) { delete "/x" }.route
    end

    def test_query_defines_query_route
      assert_equal ["QUERY", "/x"], Class.new(Boto::Endpoint) { query "/x" }.route
    end

    def test_query_after_another_verb_raises_route_error
      error = assert_raises(Boto::Endpoint::RouteError) do
        Class.new(Boto::Endpoint) do
          get "/x"
          query "/y"
        end
      end
      assert_equal "route already defined: GET /x", error.message
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

    def test_body_defines_body_schema
      endpoint = Class.new(Boto::Endpoint) { body EndpointTestSchemas::UserSchema }
      assert_same EndpointTestSchemas::UserSchema, endpoint.body_schema
    end

    def test_body_rejects_non_schema_classes
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { body String } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { body Boto::Schema } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { body "UserSchema" } }
    end

    def test_second_body_raises_argument_error
      assert_raises(ArgumentError) do
        Class.new(Boto::Endpoint) do
          body EndpointTestSchemas::UserSchema
          body EndpointTestSchemas::PostSchema
        end
      end
    end

    def test_returns_single_schema
      endpoint = Class.new(Boto::Endpoint) { returns EndpointTestSchemas::UserSchema }
      assert_same EndpointTestSchemas::UserSchema, endpoint.return_schema
      refute_predicate endpoint, :returns_list?
    end

    def test_returns_array_of_one_schema
      endpoint = Class.new(Boto::Endpoint) { returns [EndpointTestSchemas::UserSchema] }
      assert_same EndpointTestSchemas::UserSchema, endpoint.return_schema
      assert_predicate endpoint, :returns_list?
    end

    def test_returns_rejects_invalid_shapes
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { returns [EndpointTestSchemas::UserSchema, EndpointTestSchemas::PostSchema] } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { returns [] } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { returns String } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { returns Boto::Schema } }
    end

    def test_second_returns_raises_argument_error
      assert_raises(ArgumentError) do
        Class.new(Boto::Endpoint) do
          returns EndpointTestSchemas::UserSchema
          returns [EndpointTestSchemas::PostSchema]
        end
      end
    end

    def test_summary_defines_summary_text
      endpoint = Class.new(Boto::Endpoint) { summary "Lists users" }
      assert_equal "Lists users", endpoint.summary_text
    end

    def test_summary_rejects_blank_or_non_string
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { summary "" } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { summary "   " } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { summary nil } }
    end

    def test_errors_accumulates_sorted_without_duplicates
      endpoint = Class.new(Boto::Endpoint) do
        errors 404, 409, 404
        errors 422
      end
      assert_equal [404, 409, 422], endpoint.error_statuses
      assert_predicate endpoint.error_statuses, :frozen?
    end

    def test_errors_rejects_statuses_outside_error_range
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { errors 200 } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { errors "x" } }
    end

    def test_schema_declarations_default_to_empty
      endpoint = Class.new(Boto::Endpoint)
      assert_nil endpoint.body_schema
      assert_nil endpoint.return_schema
      refute_predicate endpoint, :returns_list?
      assert_nil endpoint.summary_text
      assert_equal [], endpoint.error_statuses
    end

    def test_compile_rejects_body_param_with_body_schema
      endpoint = Class.new(Boto::Endpoint) do
        param :body, String
        body EndpointTestSchemas::UserSchema
      end
      error = assert_raises(ArgumentError) { endpoint.compile! }
      assert_equal "param :body conflicts with the body schema", error.message
    end

    def test_compile_compiles_body_and_return_schemas
      endpoint = Class.new(Boto::Endpoint) do
        body EndpointTestSchemas::PostSchema
        returns [EndpointTestSchemas::UserSchema]
      end
      assert_same endpoint, endpoint.compile!
      assert_predicate EndpointTestSchemas::PostSchema, :compiled?
      assert_predicate EndpointTestSchemas::UserSchema, :compiled?
    end

    def test_skip_declares_plugin_names
      endpoint = Class.new(Boto::Endpoint) { skip :auth, :rate_limit }
      assert_equal %i[auth rate_limit], endpoint.skipped_plugins
      assert_predicate endpoint.skipped_plugins, :frozen?
    end

    def test_skip_accumulates_without_duplicates
      endpoint = Class.new(Boto::Endpoint) do
        skip :auth
        skip :auth, :rate_limit
      end
      assert_equal %i[auth rate_limit], endpoint.skipped_plugins
    end

    def test_skip_accepts_strings
      endpoint = Class.new(Boto::Endpoint) { skip "auth" }
      assert_equal %i[auth], endpoint.skipped_plugins
    end

    def test_skip_rejects_invalid_names
      ["Auth", "rate-limit", "1auth", "", "auth x", :"auth x", 1, nil].each do |name|
        assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { skip name } }
      end
    end

    def test_skip_without_arguments_raises
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { skip } }
    end

    def test_skipped_plugins_defaults_to_frozen_empty_list
      endpoint = Class.new(Boto::Endpoint)
      assert_same Boto::Endpoint::NO_SKIPS, endpoint.skipped_plugins
      assert_predicate endpoint.skipped_plugins, :frozen?
    end

    def test_authenticate_declares_strategy_and_options
      endpoint = Class.new(Boto::Endpoint) { authenticate :signature, secret: "x" }
      assert_equal [:signature, { secret: "x" }], endpoint.authentication
      assert_predicate endpoint.authentication, :frozen?
      assert_predicate endpoint.authentication.last, :frozen?
    end

    def test_authenticate_accepts_string_strategy
      endpoint = Class.new(Boto::Endpoint) { authenticate "signature" }
      assert_equal [:signature, {}], endpoint.authentication
    end

    def test_second_authenticate_raises_argument_error
      error = assert_raises(ArgumentError) do
        Class.new(Boto::Endpoint) do
          authenticate :signature
          authenticate :bearer
        end
      end
      assert_equal "authenticate already declared", error.message
    end

    def test_authenticate_rejects_invalid_strategy_name
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { authenticate "Signature" } }
      assert_raises(ArgumentError) { Class.new(Boto::Endpoint) { authenticate nil } }
    end

    def test_authentication_defaults_to_nil
      assert_nil Class.new(Boto::Endpoint).authentication
    end

    def test_compile_rejects_skip_auth_with_authenticate
      endpoint = Class.new(Boto::Endpoint) do
        skip :auth
        authenticate :signature
      end
      error = assert_raises(ArgumentError) { endpoint.compile! }
      assert_equal "skip :auth conflicts with authenticate", error.message
    end

    def test_compile_allows_skipping_other_plugins_with_authenticate
      endpoint = Class.new(Boto::Endpoint) do
        skip :rate_limit
        authenticate :signature
      end
      assert_same endpoint, endpoint.compile!
    end

    def test_principal_reads_from_env
      endpoint = Class.new(Boto::Endpoint).new({ "boto.principal" => { sub: "1" } })
      assert_equal({ sub: "1" }, endpoint.principal)
    end

    def test_principal_is_nil_without_key
      assert_nil Class.new(Boto::Endpoint).new.principal
    end
  end
end
