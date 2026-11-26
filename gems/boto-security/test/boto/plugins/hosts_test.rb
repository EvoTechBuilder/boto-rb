# frozen_string_literal: true

require "test_helper"
require "rack/mock"

class HostsTest < Minitest::Test
  APP = ->(_env) { [200, {}, ["ok"]] }
  ALLOW = ["api.loja.com", ".loja.internal"].freeze

  def build(env_name: "production", allow: ALLOW)
    Boto::Plugins::Hosts.new(env_name: env_name, allow: allow)
  end

  def status_for(plugin, host)
    env = host ? Rack::MockRequest.env_for("/", "HTTP_HOST" => host) : Rack::MockRequest.env_for("/")
    plugin.call(env, APP).first
  end

  def test_exact_host_is_allowed
    assert_equal 200, status_for(build, "api.loja.com")
  end

  def test_host_with_port_is_allowed
    assert_equal 200, status_for(build, "api.loja.com:443")
  end

  def test_host_is_case_insensitive
    assert_equal 200, status_for(build, "API.Loja.COM")
  end

  def test_suffix_matches_bare_domain_and_subdomains
    assert_equal 200, status_for(build, "loja.internal")
    assert_equal 200, status_for(build, "a.loja.internal")
  end

  def test_suffix_does_not_match_lookalike_domain
    assert_equal 403, status_for(build, "evilloja.internal")
  end

  def test_blocked_host_returns_problem_response_without_echoing_host
    status, headers, body = build.call(Rack::MockRequest.env_for("/", "HTTP_HOST" => "evil.com"), APP)

    assert_equal 403, status
    assert_equal "application/problem+json", headers["content-type"]
    refute_includes body.join, "evil.com"
  end

  def test_missing_host_is_blocked
    assert_equal 403, status_for(build, nil)
  end

  def test_development_allows_local_hosts_without_allow_list
    plugin = build(env_name: "development", allow: [])

    assert_equal 200, status_for(plugin, "localhost:3000")
    assert_equal 200, status_for(plugin, "127.0.0.1")
    assert_equal 200, status_for(plugin, "[::1]:3000")
  end

  def test_development_keeps_configured_hosts
    assert_equal 200, status_for(build(env_name: "development"), "api.loja.com")
  end

  def test_production_without_allow_raises
    error = assert_raises(ArgumentError) { build(allow: []) }

    assert_equal "hosts: allow is required outside development", error.message
  end

  def test_non_string_entry_raises
    assert_raises(ArgumentError) { build(allow: ["api.loja.com", 42]) }
  end

  def test_non_array_allow_raises
    assert_raises(ArgumentError) { build(allow: "api.loja.com") }
  end

  def test_scope_and_plugin_name
    assert_equal :global, Boto::Plugins::Hosts.scope
    assert_equal :hosts, Boto::Plugins::Hosts.plugin_name
  end
  def test_empty_or_dot_entries_are_rejected
    ["", "."].each do |entry|
      assert_raises(ArgumentError) { Boto::Plugins::Hosts.new(env_name: "production", allow: [entry]) }
    end
  end
end
