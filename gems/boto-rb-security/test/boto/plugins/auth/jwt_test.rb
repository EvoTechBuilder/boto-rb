# frozen_string_literal: true

require "test_helper"
require "jwt"
require "rack/mock"

class Boto::Plugins::Auth::JwtTest < Minitest::Test
  SECRET = "s3cret-for-tests"
  ISSUER = "boto-issuer"
  AUDIENCE = "boto-api"

  def self.rsa_key
    @rsa_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def strategy(**options)
    Boto::Plugins::Auth::Jwt.new(**{ algorithms: ["HS256"], secret: SECRET }.merge(options))
  end

  def env_with(authorization)
    Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => authorization)
  end

  def bearer(token)
    env_with("Bearer #{token}")
  end

  def hs256(claims, secret: SECRET)
    JWT.encode(claims, secret, "HS256")
  end

  def valid_claims(**extra)
    { "sub" => "user-1", "exp" => Time.now.to_i + 60 }.merge(extra.transform_keys(&:to_s))
  end

  def test_valid_hs256_token_returns_frozen_symbol_claims
    principal = strategy.authenticate(bearer(hs256(valid_claims(role: "admin"))))

    assert_equal "user-1", principal[:sub]
    assert_equal "admin", principal[:role]
    assert principal.frozen?
    assert principal.keys.all? { _1.is_a?(Symbol) }
  end

  def test_wrong_signature_is_rejected
    token = hs256(valid_claims, secret: "other-secret")

    assert_nil strategy.authenticate(bearer(token))
  end

  def test_expired_token_is_rejected
    token = hs256(valid_claims("exp" => Time.now.to_i - 10))

    assert_nil strategy.authenticate(bearer(token))
  end

  def test_token_without_exp_is_rejected
    token = hs256({ "sub" => "user-1" })

    assert_nil strategy.authenticate(bearer(token))
  end

  def test_alg_outside_allowlist_is_rejected_for_rs256_token
    key = self.class.rsa_key
    token = JWT.encode(valid_claims, key, "RS256")
    verifier = strategy(algorithms: ["HS256"], secret: SECRET)

    assert_nil verifier.authenticate(bearer(token))
  end

  def test_alg_outside_allowlist_is_rejected_for_hs256_token
    key = self.class.rsa_key
    verifier = strategy(algorithms: ["RS256"], secret: nil, public_key: key.public_key.to_pem)
    token = hs256(valid_claims)

    assert_nil verifier.authenticate(bearer(token))
  end

  def test_none_algorithm_token_is_rejected
    token = JWT.encode(valid_claims, nil, "none")

    assert_nil strategy.authenticate(bearer(token))
  end

  def test_wrong_issuer_is_rejected_when_configured
    verifier = strategy(issuer: ISSUER)

    assert_nil verifier.authenticate(bearer(hs256(valid_claims(iss: "other"))))
    refute_nil verifier.authenticate(bearer(hs256(valid_claims(iss: ISSUER))))
  end

  def test_wrong_audience_is_rejected_when_configured
    verifier = strategy(audience: AUDIENCE)

    assert_nil verifier.authenticate(bearer(hs256(valid_claims(aud: "other"))))
    refute_nil verifier.authenticate(bearer(hs256(valid_claims(aud: AUDIENCE))))
  end

  def test_issuer_and_audience_are_not_checked_when_unset
    assert strategy.authenticate(bearer(hs256(valid_claims(iss: "anything", aud: "anything"))))
  end

  def test_leeway_accepts_recently_expired_token
    token = hs256(valid_claims("exp" => Time.now.to_i - 5))

    assert_nil strategy(leeway: 0).authenticate(bearer(token))
    refute_nil strategy(leeway: 10).authenticate(bearer(token))
  end

  def test_missing_header_is_rejected
    assert_nil strategy.authenticate(Rack::MockRequest.env_for("/"))
  end

  def test_basic_scheme_is_rejected
    assert_nil strategy.authenticate(env_with("Basic dXNlcjpwYXNz"))
  end

  def test_none_in_algorithms_raises
    error = assert_raises(ArgumentError) { strategy(algorithms: ["none"]) }
    assert_match(/none/, error.message)
  end

  def test_none_in_any_case_raises
    assert_raises(ArgumentError) { strategy(algorithms: ["NoNe"]) }
  end

  def test_empty_algorithms_raises
    assert_raises(ArgumentError) { strategy(algorithms: []) }
  end

  def test_without_key_raises
    assert_raises(ArgumentError) { strategy(secret: nil) }
  end

  def test_with_secret_and_public_key_raises
    assert_raises(ArgumentError) { strategy(public_key: self.class.rsa_key.public_key.to_pem) }
  end

  def test_negative_leeway_raises
    assert_raises(ArgumentError) { strategy(leeway: -1) }
  end

  def test_secret_lambda_is_resolved
    verifier = strategy(secret: -> { SECRET })

    refute_nil verifier.authenticate(bearer(hs256(valid_claims)))
  end

  def test_rs256_with_public_key_pem_string
    key = self.class.rsa_key
    verifier = strategy(algorithms: ["RS256"], secret: nil, public_key: key.public_key.to_pem)
    token = JWT.encode(valid_claims, key, "RS256")

    principal = verifier.authenticate(bearer(token))
    assert_equal "user-1", principal[:sub]
  end

  def test_algorithms_array_of_the_caller_is_not_frozen
    algorithms = ["HS256"]

    strategy(algorithms: algorithms)

    refute_predicate algorithms, :frozen?
  end

  def test_mutating_algorithms_after_build_does_not_change_verification
    algorithms = [+"HS256"]
    verifier = strategy(algorithms: algorithms)

    algorithms[0].replace("RS256")
    algorithms << "ES256"

    refute_nil verifier.authenticate(bearer(hs256(valid_claims)))
  end

  def test_mutating_secret_after_build_does_not_change_verification
    secret = +SECRET
    verifier = strategy(secret: secret)

    secret.replace("changed")

    refute_nil verifier.authenticate(bearer(hs256(valid_claims)))
  end

  def test_secret_from_lambda_is_copied_and_frozen
    secret = +SECRET
    verifier = strategy(secret: -> { secret })

    secret.replace("changed")

    refute_nil verifier.authenticate(bearer(hs256(valid_claims)))
    assert_predicate verifier.instance_variable_get(:@key), :frozen?
  end

  def test_mutating_issuer_after_build_does_not_change_verification
    issuer = +ISSUER
    verifier = strategy(issuer: issuer)

    issuer.replace("other")

    refute_nil verifier.authenticate(bearer(hs256(valid_claims(iss: ISSUER))))
    assert_nil verifier.authenticate(bearer(hs256(valid_claims(iss: "other"))))
  end

  def test_challenge_uses_realm
    assert_equal 'Bearer realm="Boto"', strategy.challenge
    assert_equal 'Bearer realm="Api"', strategy(realm: "Api").challenge
  end

  def test_security_scheme
    assert_equal(
      { "type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT" },
      strategy.security_scheme
    )
  end
end
