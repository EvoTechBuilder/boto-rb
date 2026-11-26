# frozen_string_literal: true

require "test_helper"
require "rack/mock"

class Boto::Plugins::Auth::SignatureTest < Minitest::Test
  SECRET = "webhook-secret"
  BODY = '{"event":"order.created"}'
  NOW = 1_700_000_000

  def strategy(**options)
    Boto::Plugins::Auth::Signature.new(**{ secret: SECRET }.merge(options))
  end

  def env_for(body: BODY, headers: {})
    Rack::MockRequest.env_for("/", **headers, input: body)
  end

  def hmac(message, algorithm: "sha256", secret: SECRET)
    OpenSSL::HMAC.hexdigest(algorithm, secret, message)
  end

  def fake_clock(now)
    -> { now }
  end

  def test_valid_signature_returns_principal
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })

    assert_equal({ signed: true }, strategy.authenticate(env))
  end

  def test_valid_signature_with_prefix
    env = env_for(headers: { "HTTP_X_SIGNATURE" => "sha256=#{hmac(BODY)}" })

    assert_equal({ signed: true }, strategy(prefix: "sha256=").authenticate(env))
  end

  def test_prefix_is_required_when_configured
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })

    assert_nil strategy(prefix: "sha256=").authenticate(env)
  end

  def test_altered_body_is_rejected
    env = env_for(body: '{"event":"order.deleted"}', headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })

    assert_nil strategy.authenticate(env)
  end

  def test_missing_header_is_rejected
    assert_nil strategy.authenticate(env_for)
  end

  def test_custom_header_name_is_read
    env = env_for(headers: { "HTTP_X_HUB_SIGNATURE" => hmac(BODY) })

    assert_equal({ signed: true }, strategy(header: "X-Hub-Signature").authenticate(env))
  end

  def test_sha512_signature
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY, algorithm: "sha512") })

    assert_equal({ signed: true }, strategy(algorithm: "sha512").authenticate(env))
    assert_nil strategy(algorithm: "sha256").authenticate(env)
  end

  def test_body_remains_readable_after_authentication
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })

    strategy.authenticate(env)

    assert_equal BODY, env["rack.input"].read
  end

  def test_body_below_limit_still_authenticates
    body = "x" * 1_000
    env = env_for(body: body, headers: { "HTTP_X_SIGNATURE" => hmac(body) })

    assert_equal({ signed: true }, strategy.authenticate(env))
  end

  def test_body_above_default_limit_raises_payload_too_large
    body = "x" * (Boto::RequestBody::DEFAULT_LIMIT + 1)
    env = env_for(body: body, headers: { "HTTP_X_SIGNATURE" => hmac(body) })
    env.delete("CONTENT_LENGTH")

    assert_raises(Boto::Error::PayloadTooLarge) { strategy.authenticate(env) }
  end

  def test_body_remains_readable_when_input_cannot_rewind
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })
    env["rack.input"] = NonRewindableInput.new(BODY)

    assert_equal({ signed: true }, strategy.authenticate(env))
    assert_equal BODY, env["rack.input"].read
  end

  # Only responds to read, like a streaming input without rewind.
  class NonRewindableInput
    def initialize(content)
      @io = StringIO.new(content)
    end

    def read(*args) = @io.read(*args)
  end

  def test_tolerance_accepts_timestamp_inside_window
    message = "#{NOW - 30}.#{BODY}"
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(message), "HTTP_X_TIMESTAMP" => (NOW - 30).to_s })

    assert_equal({ signed: true }, strategy(tolerance: 300, clock: fake_clock(NOW)).authenticate(env))
  end

  def test_tolerance_rejects_timestamp_outside_window
    message = "#{NOW - 600}.#{BODY}"
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(message), "HTTP_X_TIMESTAMP" => (NOW - 600).to_s })

    assert_nil strategy(tolerance: 300, clock: fake_clock(NOW)).authenticate(env)
  end

  def test_tolerance_rejects_missing_timestamp
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })

    assert_nil strategy(tolerance: 300, clock: fake_clock(NOW)).authenticate(env)
  end

  def test_tolerance_rejects_signature_over_body_only
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY), "HTTP_X_TIMESTAMP" => NOW.to_s })

    assert_nil strategy(tolerance: 300, clock: fake_clock(NOW)).authenticate(env)
  end

  def test_custom_timestamp_header_is_read
    message = "#{NOW}.#{BODY}"
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(message), "HTTP_X_SENT_AT" => NOW.to_s })

    assert_equal({ signed: true },
                 strategy(tolerance: 300, timestamp_header: "X-Sent-At", clock: fake_clock(NOW)).authenticate(env))
  end

  def test_invalid_algorithm_raises
    assert_raises(ArgumentError) { strategy(algorithm: "md5") }
  end

  def test_empty_secret_raises
    assert_raises(ArgumentError) { strategy(secret: "") }
    assert_raises(ArgumentError) { strategy(secret: nil) }
  end

  def test_secret_lambda_is_resolved
    env = env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })

    assert_equal({ signed: true }, strategy(secret: -> { SECRET }).authenticate(env))
  end

  def test_invalid_tolerance_raises
    assert_raises(ArgumentError) { strategy(tolerance: 0) }
    assert_raises(ArgumentError) { strategy(tolerance: "300") }
  end

  def test_mutating_secret_after_build_does_not_change_verification
    secret = +SECRET
    verifier = strategy(secret: secret)
    secret.replace("changed")

    assert_equal({ signed: true }, verifier.authenticate(env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })))
  end

  def test_secret_from_lambda_is_copied_and_frozen
    secret = +SECRET
    verifier = strategy(secret: -> { secret })
    secret.replace("changed")

    assert_equal({ signed: true }, verifier.authenticate(env_for(headers: { "HTTP_X_SIGNATURE" => hmac(BODY) })))
    assert_predicate verifier.instance_variable_get(:@secret), :frozen?
  end

  def test_mutating_header_and_prefix_after_build_does_not_change_verification
    header = +"X-Hub-Signature"
    prefix = +"sha256="
    verifier = strategy(header: header, prefix: prefix)

    header.replace("X-Other")
    prefix.replace("sha512=")

    env = env_for(headers: { "HTTP_X_HUB_SIGNATURE" => "sha256=#{hmac(BODY)}" })
    assert_equal({ signed: true }, verifier.authenticate(env))
    assert_equal 'Signature header="X-Hub-Signature"', verifier.challenge
  end

  def test_challenge_uses_header_name
    assert_equal 'Signature header="X-Signature"', strategy.challenge
    assert_equal 'Signature header="X-Hub-Signature"', strategy(header: "X-Hub-Signature").challenge
  end

  def test_security_scheme
    assert_equal(
      { "type" => "apiKey", "in" => "header", "name" => "X-Signature" },
      strategy.security_scheme
    )
  end

  def test_error_statuses_include_payload_too_large
    assert_equal [413], Boto::Plugins::Auth::Signature.new(secret: "s3cret").error_statuses
  end
end
