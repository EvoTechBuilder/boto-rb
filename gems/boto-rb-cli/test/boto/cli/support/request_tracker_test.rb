# frozen_string_literal: true

require "test_helper"
require "async"

class Boto::CLI::RequestTrackerTest < Minitest::Test
  OK = [200, {}, []].freeze

  def test_counts_a_request_while_it_runs
    tracker = Boto::CLI::RequestTracker.new
    seen = nil
    app = tracker.wrap(->(_env) { seen = tracker.count; OK })

    Sync { app.call({}) }

    assert_equal 1, seen
    assert_equal 0, tracker.count
  end

  def test_forgets_a_request_that_raises
    tracker = Boto::CLI::RequestTracker.new
    app = tracker.wrap(->(_env) { raise "boom" })

    Sync { assert_raises(RuntimeError) { app.call({}) } }

    assert_equal 0, tracker.count
  end

  def test_cut_all_interrupts_the_requests_still_running
    tracker = Boto::CLI::RequestTracker.new
    app = tracker.wrap(->(_env) { sleep 5; OK })
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Sync do |task|
      request = task.async { app.call({}) }
      sleep 0.01
      tracker.cut_all
      request.wait
    end

    assert_equal 0, tracker.count
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  end

  def test_counts_requests_running_at_the_same_time
    tracker = Boto::CLI::RequestTracker.new
    app = tracker.wrap(->(_env) { sleep 0.05; OK })
    seen = nil

    Sync do |task|
      2.times { task.async { app.call({}) } }
      sleep 0.01
      seen = tracker.count
    end

    assert_equal 2, seen
    assert_equal 0, tracker.count
  end
end
