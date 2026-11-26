# frozen_string_literal: true

require "test_helper"

class Boto::Plugins::Auth::BasicTest < Minitest::Test
  BASIC = Boto::Plugins::Auth::Basic
  CREDENTIALS = { "admin" => "s3cret" }.freeze

  def test_accepts_matching_credentials
    principal = strategy.authenticate(env(basic_header("admin", "s3cret")))

    assert_equal({ user: "admin" }, principal)
    assert_predicate principal, :frozen?
  end

  def test_rejects_wrong_password
    assert_nil strategy.authenticate(env(basic_header("admin", "wrong")))
  end

  def test_rejects_unknown_user_even_with_dummy_password
    assert_nil strategy.authenticate(env(basic_header("ghost", "any")))
    assert_nil strategy.authenticate(env(basic_header("ghost", BASIC::DUMMY_PASSWORD)))
  end

  def test_rejects_missing_header
    assert_nil strategy.authenticate({})
  end

  def test_rejects_header_that_is_not_base64
    assert_nil strategy.authenticate(env("Basic !!!"))
  end

  def test_rejects_header_without_colon
    assert_nil strategy.authenticate(env("Basic #{["admin"].pack("m0")}"))
  end

  def test_rejects_invalid_utf8_user_without_raising
    assert_nil strategy.authenticate(env("Basic #{["\xff:x".b].pack("m0")}"))
  end

  def test_rejects_other_scheme
    assert_nil strategy.authenticate(env("Bearer s3cret"))
  end

  def test_credentials_can_be_a_lambda
    strategy = BASIC.new(credentials: -> { CREDENTIALS })

    assert_equal({ user: "admin" }, strategy.authenticate(env(basic_header("admin", "s3cret"))))
  end

  def test_rejects_empty_credentials
    assert_raises(ArgumentError) { BASIC.new(credentials: {}) }
  end

  def test_rejects_empty_password
    assert_raises(ArgumentError) { BASIC.new(credentials: { "admin" => "" }) }
  end

  def test_mutating_credentials_after_build_does_not_change_authentication
    credentials = { "admin" => +"s3cret" }
    strategy = BASIC.new(credentials: credentials)

    credentials["admin"].replace("changed")
    credentials["ghost"] = +"any"

    assert_equal({ user: "admin" }, strategy.authenticate(env(basic_header("admin", "s3cret"))))
    assert_nil strategy.authenticate(env(basic_header("admin", "changed")))
    assert_nil strategy.authenticate(env(basic_header("ghost", "any")))
  end

  def test_credentials_from_lambda_are_copied_and_frozen
    credentials = { "admin" => +"s3cret" }
    strategy = BASIC.new(credentials: -> { credentials })

    credentials["admin"].replace("changed")

    assert_equal({ user: "admin" }, strategy.authenticate(env(basic_header("admin", "s3cret"))))
    assert_predicate strategy.instance_variable_get(:@credentials), :frozen?
  end

  def test_challenge_uses_realm
    assert_equal 'Basic realm="Boto"', strategy.challenge
    assert_equal 'Basic realm="Admin"', strategy(realm: "Admin").challenge
  end

  def test_security_scheme
    assert_equal({ "type" => "http", "scheme" => "basic" }, strategy.security_scheme)
  end

  private

  def strategy(**options)
    BASIC.new(credentials: CREDENTIALS, **options)
  end

  def env(header)
    { "HTTP_AUTHORIZATION" => header }
  end

  def basic_header(user, password)
    "Basic #{["#{user}:#{password}"].pack("m0")}"
  end
end
