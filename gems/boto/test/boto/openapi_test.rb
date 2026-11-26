# frozen_string_literal: true

require "test_helper"
require "json"

module OpenAPITestShop
  class AddressSchema < Boto::Schema
    field :street, String
    field :zip, String
  end

  class UserInputSchema < Boto::Schema
    field :name, String
    field :address, AddressSchema
  end

  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  module Users
    class Show < Boto::Endpoint
      get "/users/:id"
      param :id, Integer
      returns UserSchema
      summary "Fetch one user"
    end

    class Index < Boto::Endpoint
      get "/users"
      param :page, Integer, min: 1, default: 1
      param :ids, [Integer], required: false
      returns [UserSchema]
    end

    class Create < Boto::Endpoint
      post "/users"
      status 201
      body UserInputSchema
      returns UserSchema
      errors 409
    end

    class Destroy < Boto::Endpoint
      delete "/users/:id"
      param :id, Integer
      status 204
    end
  end

  class Health < Boto::Endpoint
    get "/health"
  end
end

# Two schemas whose schema_name is the same ("ShopUserSchema"): the first namespace segment is dropped.
module OpenAPITestLeft
  module Shop
    class UserSchema < Boto::Schema
      field :id, Integer
    end
  end
end

module OpenAPITestRight
  module Shop
    class UserSchema < Boto::Schema
      field :name, String
    end
  end
end

module OpenAPITestDup
  class Left < Boto::Endpoint
    get "/left"
    returns OpenAPITestLeft::Shop::UserSchema
  end

  class Right < Boto::Endpoint
    get "/right"
    returns OpenAPITestRight::Shop::UserSchema
  end
end

module OpenAPITestCycle
  class Parent < Boto::Schema; end

  class Child < Boto::Schema
    field :parent, Parent
  end

  class Parent
    field :child, Child
  end

  class Ping < Boto::Endpoint
    get "/ping"
    returns Parent
  end
end

class OpenAPITest < Minitest::Test
  REF_PREFIX = "#/components/schemas/"
  FIXTURE = File.expand_path("../fixtures/openapi/shop.json", __dir__)
  PROBLEM_CONTENT = "application/problem+json"
  JSON_CONTENT = "application/json"

  def setup
    @app = Boto::App.new(namespace: OpenAPITestShop, error_output: StringIO.new)
    @doc = generate(@app)
  end

  def test_openapi_constant_autoloads_with_its_inflection
    refute Boto.const_defined?(:Openapi, false)
    assert_kind_of Module, Boto::OpenAPI
  end

  def test_document_has_required_top_level_keys
    assert_equal "3.1.0", @doc["openapi"]
    assert_equal({ "title" => "Shop API", "version" => "1.0.0" }, @doc["info"])
    assert_includes @doc, "paths"
    assert_includes @doc, "components"
  end

  def test_paths_use_braces_and_lowercase_verbs
    assert_equal ["/health", "/users", "/users/{id}"], @doc["paths"].keys
    assert_equal %w[delete get], @doc["paths"]["/users/{id}"].keys
  end

  def test_operation_ids_and_summary
    assert_equal "UsersShow", operation("/users/{id}", "get")["operationId"]
    assert_equal "UsersDestroy", operation("/users/{id}", "delete")["operationId"]
    assert_equal "Health", operation("/health", "get")["operationId"]
    assert_equal "Fetch one user", operation("/users/{id}", "get")["summary"]
    refute_includes operation("/users", "get"), "summary"
  end

  def test_path_param_is_required_integer
    expected = [{ "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } }]

    assert_equal expected, operation("/users/{id}", "get")["parameters"]
  end

  def test_query_params_carry_default_minimum_and_array_type
    parameters = operation("/users", "get")["parameters"]

    assert_equal(
      { "name" => "page", "in" => "query", "required" => false,
        "schema" => { "type" => "integer", "minimum" => 1, "default" => 1 } },
      parameters[0]
    )
    assert_equal(
      { "name" => "ids", "in" => "query", "required" => false,
        "schema" => { "type" => "array", "items" => { "type" => "integer" } } },
      parameters[1]
    )
  end

  def test_create_has_request_body_ref
    expected = { "required" => true,
                 "content" => { JSON_CONTENT => { "schema" => { "$ref" => "#{REF_PREFIX}UserInputSchema" } } } }

    assert_equal expected, operation("/users", "post")["requestBody"]
  end

  def test_create_responds_201_with_ref_and_problem_errors
    responses = operation("/users", "post")["responses"]

    assert_equal "Created", responses["201"]["description"]
    assert_equal({ "$ref" => "#{REF_PREFIX}UserSchema" }, responses["201"]["content"][JSON_CONTENT]["schema"])
    assert_equal "Conflict", responses["409"]["description"]
    assert_equal problem_response("Unprocessable Content"), responses["422"]
    assert_equal problem_response("Conflict"), responses["409"]
  end

  def test_destroy_responds_204_without_content_and_404_problem
    responses = operation("/users/{id}", "delete")["responses"]

    assert_equal %w[204 404 422], responses.keys
    refute_includes responses["204"], "content"
    assert_equal problem_response("Not Found"), responses["404"]
  end

  def test_health_has_only_200_with_empty_schema
    health = operation("/health", "get")

    refute_includes health, "parameters"
    refute_includes health, "requestBody"
    assert_equal({ "200" => { "description" => "OK", "content" => { JSON_CONTENT => { "schema" => {} } } } },
                 health["responses"])
  end

  def test_index_responds_array_of_user_schema
    schema = operation("/users", "get")["responses"]["200"]["content"][JSON_CONTENT]["schema"]

    assert_equal({ "type" => "array", "items" => { "$ref" => "#{REF_PREFIX}UserSchema" } }, schema)
  end

  def test_components_include_nested_schemas_and_problem
    schemas = @doc["components"]["schemas"]

    assert_equal %w[AddressSchema Problem UserInputSchema UserSchema], schemas.keys
    assert_equal %w[type title status], schemas["Problem"]["required"]
    assert_equal({ "type" => "string" }, schemas["AddressSchema"]["properties"]["zip"])
  end

  def test_every_ref_resolves_to_a_component
    refs = collect_refs(@doc)
    schemas = @doc["components"]["schemas"]

    refute_empty refs
    refs.each do |ref|
      assert ref.start_with?(REF_PREFIX), "unexpected ref #{ref}"
      assert_includes schemas, ref.delete_prefix(REF_PREFIX)
    end
  end

  def test_different_schemas_with_same_name_raise
    app = Boto::App.new(namespace: OpenAPITestDup, error_output: StringIO.new)

    error = assert_raises(ArgumentError) { generate(app) }
    assert_match(/ShopUserSchema/, error.message)
  end

  def test_recursive_schemas_are_listed_once
    app = Boto::App.new(namespace: OpenAPITestCycle, error_output: StringIO.new)

    schemas = generate(app)["components"]["schemas"]

    assert_equal %w[Child Parent Problem], schemas.keys.sort
  end

  def test_matches_shop_snapshot
    assert_equal File.read(FIXTURE), "#{JSON.pretty_generate(@doc)}\n"
  end

  private

  def generate(app)
    Boto::OpenAPI.generate(app, title: "Shop API", version: "1.0.0")
  end

  def operation(path, verb)
    @doc["paths"].fetch(path).fetch(verb)
  end

  def problem_response(description)
    { "description" => description, "content" => { PROBLEM_CONTENT => { "schema" => { "$ref" => "#{REF_PREFIX}Problem" } } } }
  end

  def collect_refs(node, found = [])
    case node
    when Hash
      node.each do |key, value|
        found << value if key == "$ref"
        collect_refs(value, found)
      end
    when Array
      node.each { |item| collect_refs(item, found) }
    end
    found
  end
end

module OpenAPITestReserved
  class Problem < Boto::Schema
    field :code, String
  end

  class Fail < Boto::Endpoint
    get "/fail"
    returns OpenAPITestReserved::Problem
    def call = { code: "x" }
  end
end

class Boto::OpenAPIReservedNameTest < Minitest::Test
  def test_user_schema_named_problem_is_rejected
    app = Boto::App.new(namespace: OpenAPITestReserved, error_output: StringIO.new)
    error = assert_raises(ArgumentError) { Boto::OpenAPI.generate(app, title: "x", version: "1") }
    assert_includes error.message, "reserved"
  end
end
