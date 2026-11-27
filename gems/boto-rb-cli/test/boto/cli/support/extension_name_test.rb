# frozen_string_literal: true

require "test_helper"

class Boto::CLI::ExtensionNameTest < Minitest::Test
  EXTENSION_NAME = Boto::CLI::ExtensionName

  def test_strips_the_boto_prefixes
    assert_equal "gateway", EXTENSION_NAME.new("boto-rb-gateway").extension
    assert_equal "audit", EXTENSION_NAME.new("boto-audit").extension
  end

  def test_keeps_other_names_and_turns_hyphens_into_underscores
    assert_equal "acme_boto_audit", EXTENSION_NAME.new("acme-boto-audit").extension
  end

  def test_override_replaces_the_derived_extension
    name = EXTENSION_NAME.new("boto-rb-gateway", override: "gw")

    assert_equal "gw", name.extension
    assert_equal "boto-rb-gateway", name.gem_name
  end

  def test_module_name_is_camel_case
    assert_equal "Gateway", EXTENSION_NAME.new("boto-rb-gateway").module_name
    assert_equal "AcmeBotoAudit", EXTENSION_NAME.new("acme-boto-audit").module_name
  end

  def test_invalid_gem_name_raises
    ["Boto-rb-gw", "-gw", "gw.rb", ""].each do |gem_name|
      error = assert_raises(Boto::CLI::Error) { EXTENSION_NAME.new(gem_name) }
      assert_equal %(invalid gem name "#{gem_name}"), error.message
    end
  end

  def test_prefix_alone_leaves_no_extension
    error = assert_raises(Boto::CLI::Error) { EXTENSION_NAME.new("boto-rb-") }
    assert_match(/\Ainvalid extension name ""/, error.message)
  end

  def test_invalid_override_raises
    ["Gw", "1gw", "gw-x"].each do |override|
      error = assert_raises(Boto::CLI::Error) { EXTENSION_NAME.new("boto-rb-gateway", override: override) }
      assert_match(/\Ainvalid extension name "#{override}"/, error.message)
    end
  end

  def test_check_name_accepts_the_app_use_format
    EXTENSION_NAME.check_name!("plugin", "audit_2")
  end

  def test_check_name_rejects_other_formats
    error = assert_raises(Boto::CLI::Error) { EXTENSION_NAME.check_name!("template", "Audit") }
    assert_match(/\Ainvalid template name "Audit"/, error.message)
  end
end
