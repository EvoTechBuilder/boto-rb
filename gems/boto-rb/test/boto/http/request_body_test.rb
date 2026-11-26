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

    def test_read_returns_body_below_limit
      assert_equal '{"a":1}', RequestBody.read(env_for('{"a":1}'))
    end

    def test_read_accepts_body_exactly_at_limit
      assert_equal "0123456789", RequestBody.read(env_for("0123456789"), limit: 10)
    end

    def test_read_body_above_limit_raises_payload_too_large
      assert_raises(Boto::Error::PayloadTooLarge) { RequestBody.read(env_for("01234567890"), limit: 10) }
    end

    def test_read_declared_length_above_limit_raises_without_reading_input
      env = { "CONTENT_LENGTH" => "2000000", "rack.input" => UnreadableInput.new }

      assert_raises(Boto::Error::PayloadTooLarge) { RequestBody.read(env, limit: 10) }
    end

    def test_read_without_input_returns_empty_string
      assert_equal "", RequestBody.read({})
    end

    # Fails the test if anything tries to read it.
    class UnreadableInput
      def read(*) = raise("input must not be read")
    end
  end
end
