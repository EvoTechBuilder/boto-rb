# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../support/results"

class BenchResultsTest < Minitest::Test
  def test_median_of_odd_count
    assert_equal 3, BenchResults.median([5, 1, 3])
  end

  def test_median_of_even_count_averages_middle_pair
    assert_in_delta 2.5, BenchResults.median([4, 1, 3, 2])
  end

  def test_summarize_takes_medians_and_allocations
    samples = [{ rps: 100.0, p99_ms: 5.0 }, { rps: 300.0, p99_ms: 1.0 }, { rps: 200.0, p99_ms: 3.0 }]
    assert_equal({ "rps" => 200.0, "p99_ms" => 3.0, "allocations" => 12.0 },
                 BenchResults.summarize(samples, allocations: 12.0))
  end

  def test_document_adds_environment_keys
    document = BenchResults.document({ "boto" => {} }, tool: "ab", ruby: "4.0.10", yjit: true)
    assert_equal({ "boto" => {}, "tool" => "ab", "ruby" => "4.0.10", "yjit" => true }, document)
  end
end
