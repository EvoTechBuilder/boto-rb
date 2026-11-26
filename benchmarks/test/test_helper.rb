# frozen_string_literal: true

require "minitest/autorun"
require "rack"
require "rack/builder"
require_relative "../support/scenarios"

# Scenario lists depend on Redis being reachable. Tests pin the answer instead of probing a real server.
# Minitest 6 has no minitest/mock here, so the override is a singleton method restored in ensure.
module RedisStubs
  def with_redis(&block) = with_redis_availability(true, &block)

  def without_redis(&block) = with_redis_availability(false, &block)

  private

  def with_redis_availability(available)
    original = BenchScenarios.method(:redis_available?)
    BenchScenarios.define_singleton_method(:redis_available?) { available }
    yield
  ensure
    BenchScenarios.define_singleton_method(:redis_available?, original)
  end
end

Minitest::Test.include(RedisStubs)
