# frozen_string_literal: true

require "test_helper"
require "support/fake_template_gem"

class Boto::ProjectTest < Minitest::Test
  def build(name, template: :library)
    Boto::Project.new(name: name, template: template, refs: [], line: 1)
  end

  def test_library_path_uses_libs_directory
    assert_equal "libs/domain", build("domain").path
  end

  def test_webapi_path_uses_apps_directory
    assert_equal "apps/orders", build("orders", template: :webapi).path
  end

  def test_microservice_path_uses_apps_directory
    assert_equal "apps/orders", build("orders", template: :microservice).path
  end

  def test_worker_path_uses_workers_directory
    assert_equal "workers/mailer", build("mailer", template: :worker).path
  end

  def test_spa_path_uses_apps_directory
    assert_equal "apps/admin", build("admin", template: :spa).path
  end

  def test_webapi_and_microservice_have_legacy_path_in_services
    assert_equal "services/orders", build("orders", template: :webapi).legacy_path
    assert_equal "services/orders", build("orders", template: :microservice).legacy_path
  end

  def test_other_templates_have_no_legacy_path
    assert_nil build("domain").legacy_path
    assert_nil build("mailer", template: :worker).legacy_path
    assert_nil build("admin", template: :spa).legacy_path
  end

  def test_gem_template_uses_its_declared_folder_and_no_legacy_path
    gem = FakeTemplateGem.new
    gem.write("demo", %(Boto::Template.define(:demo) { |t| t.folder "workers"; t.http true }\n))
    gem.activate

    assert_equal "workers/x", build("x", template: :demo).path
    assert_nil build("x", template: :demo).legacy_path
  ensure
    gem&.cleanup
  end

  def test_namespace_name_camelizes_single_word
    assert_equal "Orders", build("orders").namespace_name
  end

  def test_namespace_name_camelizes_underscored_name
    assert_equal "OrderItems", build("order_items").namespace_name
  end

  def test_generators_default_to_empty_frozen_hash
    assert_equal({}, build("domain").generators)
    assert_predicate build("domain").generators, :frozen?
  end

  def test_generators_are_kept_frozen_copy
    options = { tests: false }
    project = Boto::Project.new(name: "domain", template: :library, refs: [], line: 1, generators: options)

    assert_equal({ tests: false }, project.generators)
    assert_predicate project.generators, :frozen?
    refute_predicate options, :frozen?
  end
end
