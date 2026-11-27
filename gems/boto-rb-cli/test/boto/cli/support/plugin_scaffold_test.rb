# frozen_string_literal: true

require "test_helper"

class Boto::CLI::PluginScaffoldTest < Minitest::Test
  SCAFFOLD = Boto::CLI::PluginScaffold

  def test_base_only_without_plugin_or_template
    assert_equal %w[base], part_names(scaffold("boto-rb-gateway"))
  end

  def test_plugin_with_the_extension_name_has_no_shim
    assert_equal %w[base plugin], part_names(scaffold("boto-rb-gateway", plugin: "gateway"))
  end

  def test_plugin_named_differently_adds_the_shim
    assert_equal %w[base plugin shim], part_names(scaffold("acme-boto-audit", plugin: "audit"))
  end

  def test_template_adds_its_part
    assert_equal %w[base template], part_names(scaffold("boto-rb-gateway", template: "gateway"))
  end

  def test_locals_default_to_apps_without_http
    locals = scaffold("boto-rb-gateway", template: "gateway").locals

    assert_equal "apps", locals[:folder]
    assert_equal false, locals[:http]
    assert_equal "Gateway", locals[:template_class]
  end

  def test_locals_carry_the_plugin_shim_and_requirement
    locals = scaffold("acme-boto-audit", plugin: "audit", folder: "libs", http: true).locals

    assert_equal "audit", locals[:shim_plugin]
    assert_equal "Audit", locals[:plugin_class]
    assert_equal "libs", locals[:folder]
    assert_equal true, locals[:http]
    assert_match(/\A~> \d+\.\d+\.0\z/, locals[:boto_requirement])
  end

  private

  def scaffold(gem_name, options = {})
    SCAFFOLD.new(Boto::CLI::ExtensionName.new(gem_name), options, year: 2026)
  end

  def part_names(scaffold)
    scaffold.directories.map { |directory| File.basename(directory) }
  end
end
