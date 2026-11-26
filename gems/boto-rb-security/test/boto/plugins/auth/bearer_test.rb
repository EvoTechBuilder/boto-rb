# frozen_string_literal: true

require "test_helper"

class Boto::Plugins::Auth::BearerTest < Minitest::Test
  BEARER = Boto::Plugins::Auth::Bearer
  TOKENS = %w[alpha beta].freeze

  def test_accepts_token_and_reports_its_index
    assert_equal({ token_index: 1 }, strategy.authenticate(env("Bearer beta")))
    assert_equal({ token_index: 0 }, strategy.authenticate(env("Bearer alpha")))
  end

  def test_principal_is_frozen
    assert_predicate strategy.authenticate(env("Bearer beta")), :frozen?
  end

  def test_rejects_wrong_token
    assert_nil strategy.authenticate(env("Bearer gamma"))
  end

  def test_rejects_missing_header
    assert_nil strategy.authenticate({})
  end

  def test_rejects_other_scheme
    assert_nil strategy.authenticate(env("Basic YWxwaGE6eA=="))
  end

  def test_tokens_can_be_a_lambda
    strategy = BEARER.new(tokens: -> { TOKENS })

    assert_equal({ token_index: 1 }, strategy.authenticate(env("Bearer beta")))
  end

  def test_rejects_empty_token_list
    assert_raises(ArgumentError) { BEARER.new(tokens: []) }
  end

  def test_rejects_tokens_that_are_not_an_array
    assert_raises(ArgumentError) { BEARER.new(tokens: "alpha") }
  end

  def test_challenge_uses_realm
    assert_equal 'Bearer realm="Boto"', strategy.challenge
    assert_equal 'Bearer realm="Api"', strategy(realm: "Api").challenge
  end

  def test_security_scheme
    assert_equal({ "type" => "http", "scheme" => "bearer" }, strategy.security_scheme)
  end

  private

  def strategy(**options)
    BEARER.new(tokens: TOKENS, **options)
  end

  def env(header)
    { "HTTP_AUTHORIZATION" => header }
  end
end
