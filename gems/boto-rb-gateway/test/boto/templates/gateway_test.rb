# frozen_string_literal: true

require "test_helper"

class GatewayTemplateTest < Minitest::Test
  def setup
    Boto::Templates.reset!
  end

  def test_registers_the_template
    assert Boto::Templates.key?(:gateway)

    template = Boto::Templates.fetch(:gateway)
    assert_equal "apps", template.folder
    assert_equal true, template.http
    assert_equal true, template.mounts_refs
  end
end
