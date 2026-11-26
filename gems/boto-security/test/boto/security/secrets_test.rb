# frozen_string_literal: true

require "test_helper"

class Boto::Security::SecretsTest < Minitest::Test
  def test_resolve_calls_lambdas_and_keeps_values
    assert_equal "s3cret", Boto::Security::Secrets.resolve(-> { "s3cret" })
    assert_equal %w[a b], Boto::Security::Secrets.resolve(%w[a b])
  end

  def test_equal_compares_content
    assert Boto::Security::Secrets.equal?("token", "token")
    refute Boto::Security::Secrets.equal?("token", "tokem")
    refute Boto::Security::Secrets.equal?("token", "token-longer")
  end

  def test_equal_is_false_with_nil
    refute Boto::Security::Secrets.equal?(nil, "token")
    refute Boto::Security::Secrets.equal?("token", nil)
  end
end
