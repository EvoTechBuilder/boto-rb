# frozen_string_literal: true

require "test_helper"

# Injected client: the statuses depend only on on_error, so no Redis connection is needed.
class Boto::Redis::RateLimitStoreErrorStatusesTest < Minitest::Test
  def test_deny_answers_503
    assert_equal [503], build_store(on_error: :deny).error_statuses
  end

  def test_allow_declares_no_statuses
    assert_empty build_store(on_error: :allow).error_statuses
  end

  private

  def build_store(**options)
    Boto::Redis::RateLimitStore.new(client: Object.new, **options)
  end
end
