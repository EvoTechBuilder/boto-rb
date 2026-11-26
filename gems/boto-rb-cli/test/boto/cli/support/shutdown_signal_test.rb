# frozen_string_literal: true

require "test_helper"
require "async"

class Boto::CLI::ShutdownSignalTest < Minitest::Test
  POLL = 0.01
  MAX_POLLS = 100

  def test_wait_returns_after_a_signal
    signal = Boto::CLI::ShutdownSignal.new

    signal.install do
      Sync do
        Process.kill("TERM", Process.pid)
        signal.wait
      end
    end

    refute signal.repeated?
  end

  def test_a_second_signal_counts_as_repeated
    signal = Boto::CLI::ShutdownSignal.new

    signal.install do
      Sync do
        Process.kill("TERM", Process.pid)
        signal.wait
        Process.kill("INT", Process.pid)
        MAX_POLLS.times { break if signal.repeated?; sleep POLL }
      end
    end

    assert signal.repeated?
  end

  def test_install_restores_the_previous_handler
    previous = ->(_signo) {}
    old = trap("TERM", previous)
    begin
      Boto::CLI::ShutdownSignal.new.install {}

      assert_same previous, trap("TERM", old)
    ensure
      trap("TERM", old)
    end
  end
end
