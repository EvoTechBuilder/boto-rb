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
      assert_equal 401, Error::Unauthorized.new.status
      assert_equal 403, Error::Forbidden.new.status
      assert_equal 429, Error::TooManyRequests.new(1).status
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

    def test_unauthorized_sends_www_authenticate_challenge
      challenge = 'Bearer realm="api"'
      error = Error::Unauthorized.new(challenge)
      status, headers, _body = error.to_response

      assert_equal 401, status
      assert_equal challenge, error.challenge
      assert_equal({ "www-authenticate" => challenge }, error.headers)
      assert_equal challenge, headers["www-authenticate"]
    end

    def test_unauthorized_without_challenge_has_no_headers
      error = Error::Unauthorized.new

      assert_nil error.challenge
      assert_empty error.headers
      assert_predicate error.headers, :frozen?
      assert_equal "Unauthorized", error.message
    end

    def test_unauthorized_keeps_custom_detail
      error = Error::Unauthorized.new(nil, "token expired")

      assert_equal "token expired", error.detail
    end

    def test_forbidden_to_response
      status, _headers, body = Error::Forbidden.new("not your order").to_response
      json = JSON.parse(body.first)

      assert_equal 403, status
      assert_equal "Forbidden", json["title"]
      assert_equal "not your order", json["detail"]
    end

    def test_too_many_requests_sends_retry_after
      error = Error::TooManyRequests.new(30, "slow down")
      status, headers, _body = error.to_response

      assert_equal 429, status
      assert_equal 30, error.retry_after
      assert_equal "30", headers["retry-after"]
      assert_equal "slow down", error.detail
    end

    def test_service_unavailable_status_and_default_message
      error = Error::ServiceUnavailable.new

      assert_equal 503, error.status
      assert_equal "Service Unavailable", error.message
      assert_nil error.retry_after
    end

    def test_service_unavailable_sends_retry_after_when_given
      error = Error::ServiceUnavailable.new("store down", retry_after: 5)

      assert_equal 5, error.retry_after
      assert_equal({ "retry-after" => "5" }, error.headers)
    end

    def test_service_unavailable_without_retry_after_has_empty_headers
      error = Error::ServiceUnavailable.new("store down")

      assert_empty error.headers
      assert_predicate error.headers, :frozen?
    end

    def test_service_unavailable_to_response_is_problem_json
      status, headers, body = Error::ServiceUnavailable.new("store down", retry_after: 5).to_response
      json = JSON.parse(body.first)

      assert_equal 503, status
      assert_equal "application/problem+json", headers["content-type"]
      assert_equal "5", headers["retry-after"]
      assert_equal "Service Unavailable", json["title"]
      assert_equal "store down", json["detail"]
    end

    def test_all_subclasses_are_boto_errors
      [
        Error::BadRequest.new,
        Error::NotFound.new,
        Error::MethodNotAllowed.new(["GET"]),
        Error::PayloadTooLarge.new,
        Error::Unprocessable.new([]),
        Error::Unauthorized.new,
        Error::Forbidden.new,
        Error::TooManyRequests.new(1),
        Error::ServiceUnavailable.new
      ].each { |error| assert_kind_of Error, error }
    end
  end
end
