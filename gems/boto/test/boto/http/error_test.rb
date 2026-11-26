# frozen_string_literal: true

require "test_helper"
require "json"

module Boto
  class ErrorTest < Minitest::Test
    def test_subclasses_have_expected_status
      assert_equal 400, Error::BadRequest.new.status
      assert_equal 404, Error::NotFound.new.status
      assert_equal 405, Error::MethodNotAllowed.new(["GET"]).status
      assert_equal 413, Error::PayloadTooLarge.new.status
      assert_equal 422, Error::Unprocessable.new([]).status
    end

    def test_base_status_is_500
      assert_equal 500, Error.new.status
    end

    def test_default_message_comes_from_http_title
      assert_equal "Not Found", Error::NotFound.new.message
      assert_equal Rack::Utils::HTTP_STATUS_CODES.fetch(422), Error::Unprocessable.new([]).message
    end

    def test_custom_detail_is_used_as_message_and_detail
      error = Error::NotFound.new("no such order")

      assert_equal "no such order", error.message
      assert_equal "no such order", error.detail
    end

    def test_not_found_to_response
      status, headers, body = Error::NotFound.new.to_response
      json = JSON.parse(body.first)

      assert_equal 404, status
      assert_equal "application/problem+json", headers["content-type"]
      assert_equal "Not Found", json["title"]
      refute json.key?("detail")
    end

    def test_method_not_allowed_sets_allow_header
      _status, headers, _body = Error::MethodNotAllowed.new(%w[GET POST]).to_response

      assert_equal "GET, POST", headers["allow"]
    end

    def test_method_not_allowed_keeps_custom_detail
      error = Error::MethodNotAllowed.new(["GET"], "use GET")

      assert_equal "use GET", error.detail
      assert_equal ["GET"], error.allowed
    end

    def test_unprocessable_includes_errors_in_json
      errors = [{ param: "email", message: "is invalid" }]
      _status, _headers, body = Error::Unprocessable.new(errors).to_response
      json = JSON.parse(body.first)

      assert_equal [{ "param" => "email", "message" => "is invalid" }], json["errors"]
    end

    def test_base_error_has_no_errors_and_empty_headers
      error = Error::BadRequest.new

      assert_nil error.errors
      assert_empty error.headers
      assert_predicate error.headers, :frozen?
    end

    def test_all_subclasses_are_boto_errors
      [
        Error::BadRequest.new,
        Error::NotFound.new,
        Error::MethodNotAllowed.new(["GET"]),
        Error::PayloadTooLarge.new,
        Error::Unprocessable.new([])
      ].each { |error| assert_kind_of Error, error }
    end
  end
end
