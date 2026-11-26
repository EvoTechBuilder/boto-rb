# frozen_string_literal: true

require "test_helper"
require "rack/mock"

module Boto
  class RequestBodyTest < Minitest::Test
    JSON_TYPE = "application/json"

    def env_for(input, content_type: JSON_TYPE)
      Rack::MockRequest.env_for("/", method: "POST", input: input, "CONTENT_TYPE" => content_type)
    end

    def test_parses_json_object
      assert_equal({ "a" => 1 }, RequestBody.parse(env_for('{"a":1}')))
    end

    def test_accepts_problem_json_and_parameterized_content_type
      assert_equal({ "a" => 1 }, RequestBody.parse(env_for('{"a":1}', content_type: "application/problem+json")))
      assert_equal({ "a" => 1 },
                   RequestBody.parse(env_for('{"a":1}', content_type: "application/json; charset=utf-8")))
    end

    def test_non_json_content_type_returns_empty
      assert_same RequestBody::EMPTY, RequestBody.parse(env_for('{"a":1}', content_type: "text/plain"))
    end

    def test_empty_body_returns_empty
      assert_same RequestBody::EMPTY, RequestBody.parse(env_for(""))
    end

    def test_invalid_json_raises_bad_request
      error = assert_raises(Boto::Error::BadRequest) { RequestBody.parse(env_for("{nope")) }
      assert_equal "invalid JSON body", error.detail
    end

    def test_non_object_json_raises_bad_request
      error = assert_raises(Boto::Error::BadRequest) { RequestBody.parse(env_for("[1,2]")) }
      assert_equal "JSON body must be an object", error.detail
    end

    def test_declared_length_above_limit_raises_payload_too_large
      env = env_for('{"a":1}')
      env["CONTENT_LENGTH"] = "2000000"
      assert_raises(Boto::Error::PayloadTooLarge) { RequestBody.parse(env, limit: 4) }
    end

    def test_body_above_limit_without_content_length_raises_payload_too_large
      env = env_for('{"a":1}')
      env.delete("CONTENT_LENGTH")
      assert_raises(Boto::Error::PayloadTooLarge) { RequestBody.parse(env, limit: 4) }
    end
  end
end
