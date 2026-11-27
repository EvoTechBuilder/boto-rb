# frozen_string_literal: true

require "test_helper"

class Boto::CLI::PortPlanTest < Minitest::Test
  HOST = "127.0.0.1"
  BASE = 3000

  def test_projects_without_a_port_take_the_sequence_from_the_base
    result = plan([entry("a"), entry("b"), entry("c")])

    assert_equal({ "a" => 3000, "b" => 3001, "c" => 3002 }, result.ports)
    assert_empty result.random
    assert_empty result.gateways
  end

  def test_declared_port_replaces_the_sequence_and_the_sequence_skips_it
    result = plan([entry("a", port: "3001"), entry("b"), entry("c")])

    assert_equal({ "a" => 3001, "b" => 3000, "c" => 3002 }, result.ports)
  end

  def test_port_zero_asks_for_a_free_port
    result = plan([entry("a", port: "0")], free: free_ports(6001))

    assert_equal({ "a" => 6001 }, result.ports)
    assert_equal %w[a], result.random
  end

  def test_a_free_port_already_taken_is_asked_again
    result = plan([entry("a", port: "6001"), entry("b", port: "0"), entry("c", port: "0")], free: free_ports(6001, 6002, 6002, 6003))

    assert_equal({ "a" => 6001, "b" => 6002, "c" => 6003 }, result.ports)
  end

  def test_gateway_takes_its_own_port_or_the_base
    result = plan([entry("borda", gateway: true, refs: %w[catalogo]), entry("catalogo", port: "4101")])
    assert_equal({ "borda" => 3000, "catalogo" => 4101 }, result.ports)
    assert_equal({ "borda" => %w[catalogo] }, result.gateways)

    assert_equal 4000, plan([entry("borda", gateway: true, port: "4000")]).ports["borda"]
  end

  def test_refs_of_a_gateway_without_a_port_get_a_free_port_and_others_the_sequence
    entries = [entry("borda", gateway: true, refs: %w[users]), entry("users"), entry("other")]
    result = plan(entries, free: free_ports(6001))

    assert_equal({ "borda" => 3000, "users" => 6001, "other" => 3001 }, result.ports)
    assert_equal %w[users], result.random
  end

  def test_invalid_port_raises
    ["abc", "", "-1", "70000", "4101 "].each do |value|
      error = assert_raises(Boto::CLI::Error) { plan([entry("catalogo", port: value)]) }
      assert_equal %(catalogo: invalid PORT "#{value}"), error.message
    end
  end

  def test_two_fixed_ports_on_the_same_number_raise
    error = assert_raises(Boto::CLI::Error) { plan([entry("catalogo", port: "4101"), entry("users", port: "4101")]) }

    assert_equal "catalogo and users both use PORT 4101", error.message
  end

  def test_the_gateway_base_port_counts_for_conflicts
    entries = [entry("catalogo", port: "4101"), entry("borda", gateway: true)]
    error = assert_raises(Boto::CLI::Error) { plan(entries, base: 4101) }

    assert_equal "catalogo and borda both use PORT 4101", error.message
  end

  def test_free_port_is_asked_for_the_host
    hosts = []
    free = lambda do |host|
      hosts << host
      7000
    end
    plan([entry("a", port: "0")], free: free)

    assert_equal [HOST], hosts
  end

  private

  def entry(name, refs: [], gateway: false, port: nil)
    Boto::CLI::PortPlan::Entry.new(name: name, refs: refs, gateway: gateway, declared_port: port)
  end

  def plan(entries, base: BASE, free: free_ports)
    Boto::CLI::PortPlan.new(entries: entries, base_port: base, host: HOST, free_port: free).call
  end

  def free_ports(*ports)
    ->(_host) { ports.shift }
  end
end
