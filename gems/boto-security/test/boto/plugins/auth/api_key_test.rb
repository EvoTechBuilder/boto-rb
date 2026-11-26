# frozen_string_literal: true

require "test_helper"

class Boto::Plugins::Auth::ApiKeyTest < Minitest::Test
  API_KEY = Boto::Plugins::Auth::ApiKey
  KEYS = { "ci" => "k1", "web" => "k2" }.freeze

  def test_accepts_key_from_default_header
    assert_equal({ key_id: "web" }, strategy.authenticate({ "HTTP_X_API_KEY" => "k2" }))
  end

  def test_accepts_key_from_custom_header
    strategy = API_KEY.new(keys: KEYS, header: "X-Client-Token")

    assert_equal({ key_id: "ci" }, strategy.authenticate({ "HTTP_X_CLIENT_TOKEN" => "k1" }))
  end

  def test_custom_header_does_not_accept_default_header
    strategy = API_KEY.new(keys: KEYS, header: "X-Client-Token")

    assert_nil strategy.authenticate({ "HTTP_X_API_KEY" => "k1" })
  end

  def test_rejects_wrong_key
    assert_nil strategy.authenticate({ "HTTP_X_API_KEY" => "nope" })
  end

  def test_rejects_missing_header
    assert_nil strategy.authenticate({})
  end

  def test_keys_can_be_a_lambda
    strategy = API_KEY.new(keys: -> { KEYS })

    assert_equal({ key_id: "ci" }, strategy.authenticate({ "HTTP_X_API_KEY" => "k1" }))
  end

  def test_rejects_empty_keys
    assert_raises(ArgumentError) { API_KEY.new(keys: {}) }
  end

  def test_rejects_empty_header_name
    assert_raises(ArgumentError) { API_KEY.new(keys: KEYS, header: "") }
  end

  def test_challenge
    assert_equal 'API-Key header="X-API-Key"', strategy.challenge
  end

  def test_security_scheme
    assert_equal({ "type" => "apiKey", "in" => "header", "name" => "X-API-Key" }, strategy.security_scheme)
    assert_equal(
      { "type" => "apiKey", "in" => "header", "name" => "X-Client-Token" },
      API_KEY.new(keys: KEYS, header: "X-Client-Token").security_scheme
    )
  end

  private

  def strategy
    API_KEY.new(keys: KEYS)
  end
end
