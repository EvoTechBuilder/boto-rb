# frozen_string_literal: true

require_relative "scenarios"
require_relative "server"
require_relative "results"

# Runs every framework x scenario: a fresh falcon per round, then the load tool against it.
class BenchRunner
  ROUNDS = 3
  QUICK_ROUNDS = 1

  def initialize(load_test:, allocations:, quick:)
    @load_test = load_test
    @allocations = allocations
    @rounds = quick ? QUICK_ROUNDS : ROUNDS
  end

  def run
    BenchScenarios::FRAMEWORKS.to_h do |framework|
      [framework, BenchScenarios::NAMES.to_h { |scenario| [scenario, measure(framework, scenario)] }]
    end
  end

  def measure(framework, scenario)
    samples = Array.new(@rounds) { sample(framework, scenario) }
    BenchResults.summarize(samples, allocations: @allocations.fetch(framework).fetch(scenario))
  end

  def sample(framework, scenario)
    BenchServer.open(BenchScenarios.app_path(framework, scenario)) do |server|
      path = BenchScenarios.load_path(scenario)
      server.ensure_ok!(path)
      url = "#{server.url}#{path}"
      @load_test.warm_up(url)
      @load_test.measure(url)
    end
  end
end
