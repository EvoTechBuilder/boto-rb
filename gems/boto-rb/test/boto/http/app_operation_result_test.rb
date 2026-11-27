# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "json"

module AppOperationResultTest
  class ItemSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  module Ops
    class Create < Boto::Operation
      def call = success({ id: 1, name: input })
    end

    class Noop < Boto::Operation
      def call = success
    end

    class Fail < Boto::Operation
      def call = failure(input, "failed: #{input}", stock: 0, secret: "hidden")
    end
  end

  module Items
    class Create < Boto::Endpoint
      post "/items"
      status 201
      param :name, String
      returns ItemSchema
      def call(name:) = Ops::Create.call(name)
    end

    class Nothing < Boto::Endpoint
      get "/nothing"
      def call = Ops::Noop.call
    end

    class Fail < Boto::Endpoint
      get "/fail/:code"
      param :code, String
      def call(code:) = Ops::Fail.call(code.to_sym)
    end

    class Literal < Boto::Endpoint
      get "/literal"
      returns ItemSchema
      def call = Boto::Operation::Result.success({ id: 1, name: "a" })
    end

    class LiteralFailure < Boto::Endpoint
      get "/literal-failure"
      def call = Boto::Operation::Result.failure(:not_found, "gone", secret: "hidden")
    end

    class Plain < Boto::Endpoint
      get "/plain"
      def call = { ok: true }
    end
  end
end

class AppOperationResultTest::AppTest < Minitest::Test
  JSON_TYPE = "application/json"
  PROBLEM_TYPE = "application/problem+json"
  NAMESPACE = AppOperationResultTest

  def setup
    @error_output = StringIO.new
  end

  def request
    Rack::MockRequest.new(Boto::App.new(namespace: NAMESPACE, env_name: "production", error_output: @error_output))
  end

  def json(body) = JSON.parse(body)

  def test_success_result_is_serialized_with_declared_status
    res = request.post("/items", input: JSON.generate({ name: "a" }), "CONTENT_TYPE" => JSON_TYPE)

    assert_equal 201, res.status
    assert_equal({ "id" => 1, "name" => "a" }, json(res.body))
  end

  def test_success_result_with_literal_value_is_serialized_by_returns
    res = request.get("/literal")

    assert_equal 200, res.status
    assert_equal({ "id" => 1, "name" => "a" }, json(res.body))
  end

  def test_success_with_nil_value_returns_no_content
    res = request.get("/nothing")

    assert_equal 204, res.status
    assert_empty res.body
  end

  def test_plain_return_is_unchanged
    res = request.get("/plain")

    assert_equal 200, res.status
    assert_equal({ "ok" => true }, json(res.body))
  end

  def test_failure_codes_map_to_http_status
    expected = { invalid: 422, unprocessable: 422, unauthorized: 401, forbidden: 403, not_found: 404, conflict: 409 }
    expected.each do |code, status|
      res = request.get("/fail/#{code}")

      assert_equal status, res.status, code.to_s
      assert_problem(res, status, code)
    end
  end

  def test_unknown_failure_code_is_unprocessable
    res = request.get("/fail/out_of_stock")

    assert_equal 422, res.status
    assert_problem(res, 422, :out_of_stock)
  end

  def test_failure_details_never_reach_the_body
    res = request.get("/fail/conflict")

    refute_includes res.body, "secret"
    refute_includes res.body, "stock"
    assert_equal %w[type title status detail code], json(res.body).keys
  end

  def test_literal_failure_result_is_translated
    res = request.get("/literal-failure")

    assert_equal 404, res.status
    assert_equal "gone", json(res.body)["detail"]
    refute_includes res.body, "secret"
  end

  private

  def assert_problem(res, status, code)
    body = json(res.body)

    assert_equal PROBLEM_TYPE, res.headers["content-type"]
    assert_equal Rack::Utils::HTTP_STATUS_CODES.fetch(status), body["title"]
    assert_equal status, body["status"]
    assert_equal "failed: #{code}", body["detail"]
    assert_equal code.to_s, body["code"]
  end
end
