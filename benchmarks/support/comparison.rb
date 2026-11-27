# frozen_string_literal: true

require_relative "scenarios"

# Compares only the boto numbers. Regression: rps down >10% (rounds on a shared CI runner spread ~7%), p99 up >5% and by more than 1 ms
# (ab reports whole ms), or allocations up by at least half an object per request.
module BenchComparison
  RPS_TOLERANCE = 0.10
  P99_TOLERANCE = 0.05
  P99_MIN_DIFF_MS = 1
  ALLOCATIONS_TOLERANCE = 0.5
  FRAMEWORK = "boto"
  Row = Struct.new(:scenario, :metric, :baseline, :current, :change, :regressed, keyword_init: true)

  def self.compare(current, baseline)
    BenchScenarios.scenarios_for(FRAMEWORK).flat_map do |scenario|
      compare_scenario(scenario, current.dig(FRAMEWORK, scenario), baseline.dig(FRAMEWORK, scenario))
    end
  end

  def self.compare_scenario(scenario, current, baseline)
    return [] unless current && baseline

    [
      row(scenario, "rps", baseline["rps"], current["rps"]) { |change| change < -RPS_TOLERANCE },
      row(scenario, "p99_ms", baseline["p99_ms"], current["p99_ms"]) { |change, diff| change > P99_TOLERANCE && diff > P99_MIN_DIFF_MS },
      row(scenario, "allocations", baseline["allocations"], current["allocations"]) { |_change, diff| diff >= ALLOCATIONS_TOLERANCE }
    ]
  end

  def self.row(scenario, metric, baseline, current)
    change = relative_change(baseline, current)
    regressed = block_given? && yield(change, current - baseline)
    Row.new(scenario: scenario, metric: metric, baseline: baseline, current: current, change: change, regressed: regressed)
  end

  def self.relative_change(baseline, current)
    return 0.0 if baseline.zero? && current.zero?
    return Float::INFINITY if baseline.zero?

    (current - baseline).to_f / baseline
  end

  def self.regressions(rows) = rows.select(&:regressed)
end
