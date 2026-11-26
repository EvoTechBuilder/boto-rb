# frozen_string_literal: true

require "test_helper"

class Boto::ProjectTest < Minitest::Test
  def build(name, template: :library)
    Boto::Project.new(name: name, template: template, refs: [], line: 1)
  end

  def test_library_path_uses_libs_directory
    assert_equal "libs/domain", build("domain").path
  end

  def test_webapi_path_uses_services_directory
    assert_equal "services/orders", build("orders", template: :webapi).path
  end

  def test_spa_path_uses_apps_directory
    assert_equal "apps/admin", build("admin", template: :spa).path
  end

  def test_namespace_name_camelizes_single_word
    assert_equal "Orders", build("orders").namespace_name
  end

  def test_namespace_name_camelizes_underscored_name
    assert_equal "OrderItems", build("order_items").namespace_name
  end
end
