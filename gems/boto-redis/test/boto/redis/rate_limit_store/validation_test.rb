# frozen_string_literal: true

require "test_helper"
require "stringio"

class Boto::Redis::RateLimitStore::ValidationTest < Minitest::Test
  CLIENT = Object.new.freeze
  URL = "redis://127.0.0.1:1/0"

  def test_requires_exactly_one_of_url_and_client
    assert_raises(ArgumentError) { new_store }
    assert_raises(ArgumentError) { new_store(url: URL, client: CLIENT) }
  end

  def test_url_must_be_a_string
    assert_raises(ArgumentError) { new_store(url: 1) }
  end

  def test_invalid_url_error_does_not_echo_the_url
    error = assert_raises(ArgumentError) { new_store(url: "redis://:s3cret@bad host/0") }

    assert_equal "url is not a valid Redis URL", error.message
  end

  def test_prefix_must_be_a_non_empty_string
    [nil, "", 1].each do |prefix|
      assert_raises(ArgumentError) { new_store(client: CLIENT, prefix: prefix) }
    end
  end

  def test_timeout_must_be_a_positive_numeric
    [0, -0.1, "1"].each do |timeout|
      assert_raises(ArgumentError) { new_store(client: CLIENT, timeout: timeout) }
    end
  end

  def test_pool_size_must_be_a_positive_integer
    [0, 1.5, "5"].each do |pool_size|
      assert_raises(ArgumentError) { new_store(url: URL, pool_size: pool_size) }
    end
  end

  def test_on_error_must_be_allow_or_deny
    assert_raises(ArgumentError) { new_store(client: CLIENT, on_error: :warn) }
  end

  def test_accepts_valid_options_with_url_and_client
    assert new_store(url: URL)
    assert new_store(client: CLIENT, on_error: :deny, timeout: 0.5, prefix: "app:rl")
  end

  private

  def new_store(**options)
    Boto::Redis::RateLimitStore.new(logger: StringIO.new, **options)
  end
end
