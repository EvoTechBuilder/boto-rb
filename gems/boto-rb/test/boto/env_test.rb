# frozen_string_literal: true

require "test_helper"

class Boto::EnvTest < Minitest::Test
  def setup
    @process = { "A" => "process", "B" => "process" }
    @project = { "B" => "project", "C" => "project" }
    @solution = { "C" => "solution", "D" => "solution" }
    @env = Boto::Env.new(@process, @project, @solution)
  end

  def test_strongest_layer_wins
    assert_equal "process", @env["A"]
    assert_equal "process", @env["B"]
    assert_equal "project", @env["C"]
    assert_equal "solution", @env["D"]
  end

  def test_fetch_returns_value
    assert_equal "solution", @env.fetch("D")
  end

  def test_fetch_uses_default_when_missing
    assert_equal "fallback", @env.fetch("MISSING", "fallback")
  end

  def test_fetch_uses_block_when_missing
    assert_equal "from block", @env.fetch("MISSING") { "from block" }
  end

  def test_fetch_raises_key_error_naming_the_key
    error = assert_raises(KeyError) { @env.fetch("MISSING") }
    assert_equal %(key not found: "MISSING"), error.message
  end

  def test_accepts_symbol_keys
    assert_equal "process", @env[:A]
    assert_equal "solution", @env.fetch(:D)
    assert @env.key?(:A)
  end

  def test_square_brackets_return_nil_when_missing
    assert_nil @env["MISSING"]
  end

  def test_key_predicate
    assert @env.key?("D")
    refute @env.key?("MISSING")
  end

  def test_to_h_is_the_merged_frozen_hash
    assert_equal({ "A" => "process", "B" => "process", "C" => "project", "D" => "solution" }, @env.to_h)
    assert_predicate @env.to_h, :frozen?
  end

  def test_object_is_frozen
    assert_predicate @env, :frozen?
  end

  def test_does_not_freeze_the_layers_it_receives
    layer = { "A" => "1" }
    Boto::Env.new(layer)
    refute_predicate layer, :frozen?
  end

  def test_does_not_change_the_layers_it_receives
    layer = { "A" => "1" }
    Boto::Env.new(layer, { "A" => "2", "B" => "3" })
    assert_equal({ "A" => "1" }, layer)
  end

  def test_empty_env
    env = Boto::Env.new
    assert_empty env.to_h
    assert_raises(KeyError) { env.fetch("A") }
  end

  def test_does_not_freeze_process_env
    Boto::Env.new(ENV.to_h)
    refute_predicate ENV, :frozen?
  end
end
