# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../support/options"

class BenchOptionsTest < Minitest::Test
  def test_defaults_are_all_off
    options = BenchOptions.parse([])
    refute options.quick
    refute options.save_baseline
    refute options.compare
  end

  def test_flags_turn_options_on
    options = BenchOptions.parse(["--quick", "--save-baseline", "--compare"])
    assert options.quick
    assert options.save_baseline
    assert options.compare
  end
end
