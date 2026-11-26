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

  def test_frozen_copy_deeply_freezes_a_copy_and_keeps_the_original
    original = { "users" => [+"ana", +"bia"] }

    copy = Boto::Security::Secrets.frozen_copy(original)

    assert_equal({ "users" => %w[ana bia] }, copy)
    assert_predicate copy, :frozen?
    assert_predicate copy["users"], :frozen?
    assert copy["users"].all?(&:frozen?)
    refute_predicate original, :frozen?
    refute_predicate original["users"], :frozen?
  end

  def test_frozen_copy_does_not_share_mutable_parts_with_the_original
    original = { "users" => [+"ana"] }
    copy = Boto::Security::Secrets.frozen_copy(original)

    original["users"][0].replace("changed")
    original["users"] << +"bia"

    assert_equal %w[ana], copy["users"]
  end

  def test_frozen_copy_keeps_other_objects_as_they_are
    key = Object.new

    assert_same key, Boto::Security::Secrets.frozen_copy(key)
    assert_equal 42, Boto::Security::Secrets.frozen_copy(42)
    assert_nil Boto::Security::Secrets.frozen_copy(nil)
  end

  def test_equal_is_false_with_nil
    refute Boto::Security::Secrets.equal?(nil, "token")
    refute Boto::Security::Secrets.equal?("token", nil)
  end
end
