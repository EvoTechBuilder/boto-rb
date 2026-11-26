# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../support/comparison"

class BenchComparisonTest < Minitest::Test
  def numbers(rps: 1000.0, p99_ms: 10.0, allocations: 100.0)
    { "rps" => rps, "p99_ms" => p99_ms, "allocations" => allocations }
  end

  def document(hello:, db: numbers)
    { "boto" => { "hello" => hello, "db" => db } }
  end

  def rows_for(current, baseline)
    BenchComparison.compare(current, baseline)
  end

  def regressed_metrics(current, baseline)
    BenchComparison.regressions(rows_for(current, baseline)).map(&:metric)
  end

  def test_no_change_is_not_a_regression
    base = document(hello: numbers)
    assert_empty regressed_metrics(base, base)
  end

  def test_rps_drop_over_five_percent_regresses
    assert_equal ["rps"], regressed_metrics(document(hello: numbers(rps: 940.0)), document(hello: numbers))
  end

  def test_rps_drop_within_tolerance_passes
    assert_empty regressed_metrics(document(hello: numbers(rps: 960.0)), document(hello: numbers))
  end

  def test_p99_rise_over_five_percent_and_one_ms_regresses
    assert_equal ["p99_ms"], regressed_metrics(document(hello: numbers(p99_ms: 12.0)), document(hello: numbers))
  end

  def test_p99_rise_of_one_ms_is_noise
    assert_empty regressed_metrics(document(hello: numbers(p99_ms: 11.0)), document(hello: numbers))
  end

  def test_allocation_increase_below_half_object_passes
    assert_empty regressed_metrics(document(hello: numbers(allocations: 100.3)), document(hello: numbers))
  end

  def test_allocation_increase_regresses
    assert_equal ["allocations"], regressed_metrics(document(hello: numbers(allocations: 101.0)), document(hello: numbers))
  end

  def test_allocation_decrease_passes
    assert_empty regressed_metrics(document(hello: numbers(allocations: 90.0)), document(hello: numbers))
  end

  def test_missing_scenario_in_baseline_is_skipped
    current = document(hello: numbers, db: numbers(rps: 1.0))
    baseline = { "boto" => { "hello" => numbers } }
    assert rows_for(current, baseline).all? { |row| row.scenario == "hello" }
  end

  def test_change_is_relative_to_baseline
    row = rows_for(document(hello: numbers(rps: 1100.0)), document(hello: numbers)).find { _1.metric == "rps" && _1.scenario == "hello" }
    assert_in_delta 0.1, row.change
  end
end
