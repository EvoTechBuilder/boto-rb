# frozen_string_literal: true

require "minitest/autorun"
require "rack"
require "rack/builder"
require_relative "../support/scenarios"

# Scenario lists depend on Redis being reachable and on the boto-rb-data folder. Tests pin the answers instead of
# probing a real server or the disk. Minitest 6 has no minitest/mock here, so the override is a singleton method
# restored in ensure.
module ScenarioStubs
  def with_redis(&block) = with_availability(:redis_available?, true, &block)

  def without_redis(&block) = with_availability(:redis_available?, false, &block)

  def with_data(&block) = with_availability(:data_available?, true, &block)

  def without_data(&block) = with_availability(:data_available?, false, &block)

  private

  def with_availability(name, available)
    original = BenchScenarios.method(name)
    BenchScenarios.define_singleton_method(name) { available }
    yield
  ensure
    BenchScenarios.define_singleton_method(name, original)
  end
end

Minitest::Test.include(ScenarioStubs)
