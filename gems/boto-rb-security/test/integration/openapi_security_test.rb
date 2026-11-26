# frozen_string_literal: true

require "test_helper"
require "stringio"

module OpenAPISecurityShop
  class Me < Boto::Endpoint
    get "/me"
  end

  class Health < Boto::Endpoint
    get "/health"
    skip :auth
  end

  class Webhook < Boto::Endpoint
    post "/webhook"
    authenticate :signature, secret: "s", header: "X-Signature"
  end

  class Exempt < Boto::Endpoint
    get "/exempt"
    skip :rate_limit
  end
end

class OpenAPISecurityTest < Minitest::Test
  REF_PREFIX = "#/components/schemas/"

  def test_declares_jwt_and_signature_schemes
    schemes = document["components"]["securitySchemes"]

    assert_equal %w[jwt signature], schemes.keys
    assert_equal({ "type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT" }, schemes["jwt"])
    assert_equal({ "type" => "apiKey", "in" => "header", "name" => "X-Signature" }, schemes["signature"])
  end

  def test_each_operation_requires_its_own_scheme
    assert_equal [{ "jwt" => [] }], operation("/me", "get")["security"]
    assert_equal [{ "signature" => [] }], operation("/webhook", "post")["security"]
  end

  def test_skipped_operation_is_public
    assert_equal [], operation("/health", "get")["security"]
  end

  def test_authenticated_operations_document_401
    assert_equal "Unauthorized", operation("/me", "get")["responses"]["401"]["description"]
    assert_equal "Unauthorized", operation("/webhook", "post")["responses"]["401"]["description"]
    refute_includes operation("/health", "get")["responses"], "401"
  end

  def test_rate_limited_operations_document_429
    assert_equal "Too Many Requests", operation("/me", "get")["responses"]["429"]["description"]
    assert_equal "Too Many Requests", operation("/health", "get")["responses"]["429"]["description"]
  end

  def test_operation_skipping_rate_limit_does_not_document_429
    refute_includes operation("/exempt", "get")["responses"], "429"
  end

  def test_every_ref_resolves
    refs = collect_refs(document)

    refute_empty refs
    refs.each { |ref| assert_includes document["components"]["schemas"], ref.delete_prefix(REF_PREFIX) }
  end

  private

  def document
    @document ||= Boto::OpenAPI.generate(app, title: "Secured Shop", version: "1.0.0")
  end

  def app
    config = Boto::Configuration.new(env_name: "production")
                                .use(:auth, strategy: :jwt, secret: "x", algorithms: ["HS256"])
                                .use(:rate_limit, limit: 10, period: 60)
    Boto::App.new(namespace: OpenAPISecurityShop, plugins: config.plugins, env_name: "production",
                  error_output: StringIO.new)
  end

  def operation(path, verb)
    document["paths"].fetch(path).fetch(verb)
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
