# frozen_string_literal: true

require "test_helper"
require "json"

module Boto
  class ProblemTest < Minitest::Test
    def test_body_omits_nil_keys
      _status, _headers, body = Problem.response(404)
      json = JSON.parse(body.first)

      assert_equal({ "type" => "about:blank", "title" => "Not Found", "status" => 404 }, json)
    end

    def test_body_includes_detail_and_errors_when_given
      _status, _headers, body = Problem.response(422, detail: "invalid", errors: [{ param: "a" }])
      json = JSON.parse(body.first)

      assert_equal "invalid", json["detail"]
      assert_equal [{ "param" => "a" }], json["errors"]
    end

    def test_code_is_serialized_as_string_between_detail_and_errors
      _status, _headers, body = Problem.response(422, detail: "d", errors: [{ param: "a" }], code: :invalid)

      assert_equal %w[type title status detail code errors], JSON.parse(body.first).keys
      assert_equal "invalid", JSON.parse(body.first)["code"]
    end

    def test_body_without_code_is_unchanged
      _status, _headers, body = Problem.response(409, detail: "taken")

      assert_equal %w[type title status detail], JSON.parse(body.first).keys
    end

    def test_extra_headers_are_merged_with_content_type
      _status, headers, _body = Problem.response(405, headers: { "allow" => "GET" })

      assert_equal({ "content-type" => "application/problem+json", "allow" => "GET" }, headers)
    end

    def test_title_follows_status
      _status, _headers, body = Problem.response(413)

      assert_equal Rack::Utils::HTTP_STATUS_CODES.fetch(413), JSON.parse(body.first)["title"]
    end

    def test_returns_rack_triple
      status, headers, body = Problem.response(400)

      assert_equal 400, status
      assert_kind_of Hash, headers
      assert_kind_of Array, body
      assert_equal 1, body.size
    end
  end
end
