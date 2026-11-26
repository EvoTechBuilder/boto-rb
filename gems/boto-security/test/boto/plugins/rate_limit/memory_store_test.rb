# frozen_string_literal: true

require "test_helper"

class Boto::Plugins::RateLimit::MemoryStoreTest < Minitest::Test
  PERIOD = 10

  def setup
    @now = 1.0
    @store = Boto::Plugins::RateLimit::MemoryStore.new(clock: -> { @now })
  end

  def test_counts_requests_within_the_window
    assert_equal [1, 9], @store.increment("a", PERIOD)
    assert_equal [2, 9], @store.increment("a", PERIOD)
    assert_equal [1, 9], @store.increment("b", PERIOD)
  end

  def test_resets_the_count_when_the_window_changes
    @store.increment("a", PERIOD)
    @now = 9.5
    assert_equal [2, 1], @store.increment("a", PERIOD)

    @now = 10.0
    assert_equal [1, 10], @store.increment("a", PERIOD)
  end

  def test_reset_in_rounds_up_to_whole_seconds_and_is_at_least_one
    @now = 3.2
    assert_equal [1, 7], @store.increment("a", PERIOD)

    @now = 9.999
    assert_equal [2, 1], @store.increment("a", PERIOD)
  end

  def test_drops_counters_of_past_windows
    @store.increment("a", PERIOD)
    @store.increment("b", PERIOD)
    assert_equal 2, @store.size

    @now = 10.0
    @store.increment("c", PERIOD)
    assert_equal 1, @store.size
  end

  def test_counts_concurrent_increments_without_losing_any
    threads = Array.new(4) { Thread.new { 25.times { @store.increment("k", PERIOD) } } }
    threads.each(&:join)

    assert_equal [101, 9], @store.increment("k", PERIOD)
  end
end
