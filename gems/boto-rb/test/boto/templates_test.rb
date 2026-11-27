# frozen_string_literal: true

require "test_helper"
require "support/fake_template_gem"

class Boto::TemplatesTest < Minitest::Test
  DEMO = <<~RUBY
    Boto::Template.define :demo do |t|
      t.folder "apps"
      t.http true
      t.files File.join(__dir__, "files")
    end
  RUBY

  def setup
    Boto::Templates.reset!
    @gems = []
  end

  def teardown
    @gems.each(&:cleanup)
    Boto::Templates.reset!
  end

  def fake_gem(templates = {})
    gem = FakeTemplateGem.new
    @gems << gem
    templates.each { |name, source| gem.write(name, source) }
    gem
  end

  def assert_load_error(error_class, expected_message_part, &block)
    error = assert_raises(error_class, &block)
    assert_includes error.message, expected_message_part
  end

  def test_official_templates_are_declared
    assert_equal %i[library microservice spa web webapi worker], Boto::Templates.all.map(&:name)
  end

  def test_only_http_templates_are_http
    assert Boto::Templates.http?(:webapi)
    assert Boto::Templates.http?(:microservice)
    assert Boto::Templates.http?(:web)
    refute Boto::Templates.http?(:library)
    refute Boto::Templates.http?(:worker)
    refute Boto::Templates.http?(:spa)
  end

  def test_official_templates_come_from_boto_rb
    assert_equal ["boto-rb"], Boto::Templates.all.map(&:source).uniq
    assert_equal "libs", Boto::Templates.fetch(:library).folder
    assert_equal "workers", Boto::Templates.fetch(:worker).folder
    assert_nil Boto::Templates.fetch(:webapi).files
  end

  def test_only_the_legacy_http_templates_keep_services_dir
    assert Boto::Templates.fetch(:webapi).legacy_services
    assert Boto::Templates.fetch(:microservice).legacy_services
    refute Boto::Templates.fetch(:library).legacy_services
  end

  def test_key_accepts_symbol_and_string
    assert Boto::Templates.key?(:webapi)
    assert Boto::Templates.key?("webapi")
    refute Boto::Templates.key?(:foo)
  end

  def test_unknown_template_lists_available_and_suggests_gem
    error = assert_raises(Boto::Templates::UnknownTemplateError) { Boto::Templates.fetch(:foo) }

    assert_equal "unknown template :foo (available: library, microservice, spa, web, webapi, worker; " \
                 "is its gem in the Gemfile?)", error.message
    assert_kind_of KeyError, error
  end

  def test_gem_template_is_discovered_on_load_path
    gem = fake_gem("demo" => DEMO)
    gem.activate
    template = Boto::Templates.fetch(:demo)

    assert_equal "apps", template.folder
    assert_predicate template, :http
    assert_equal File.join(gem.root, "boto", "templates", "demo", "files"), template.files
    assert_equal gem.root, template.source
  end

  def test_gem_template_is_found_as_a_gem_source_when_its_spec_is_loaded
    gem = fake_gem("demo" => DEMO)
    gem.activate
    spec = Gem::Specification.new { |s| s.name = "boto-demo"; s.version = "1.0.0" }
    spec.define_singleton_method(:full_gem_path) { gem.root }
    Gem.loaded_specs.store("boto-demo", spec)

    assert_equal "boto-demo", Boto::Templates.fetch(:demo).source
  ensure
    Gem.loaded_specs.delete("boto-demo")
  end

  def test_registry_loads_once_until_reset
    log = File.join(Dir.mktmpdir, "loads.log")
    gem = fake_gem("demo" => "File.write(#{log.inspect}, \"x\", mode: \"a\")\n#{DEMO}")
    gem.activate

    3.times { Boto::Templates.all }
    assert_equal 1, File.read(log).size

    Boto::Templates.reset!
    Boto::Templates.fetch(:demo)
    assert_equal 2, File.read(log).size
  ensure
    FileUtils.remove_entry(File.dirname(log)) if log
  end

  def test_same_template_file_on_load_path_twice_is_not_a_duplicate
    gem = fake_gem("demo" => DEMO)
    gem.activate
    gem.activate

    assert_equal :demo, Boto::Templates.fetch(:demo).name
  end

  def test_same_template_in_two_gems_is_refused_citing_both
    first = fake_gem("demo" => DEMO)
    second = fake_gem("demo" => DEMO)
    first.activate
    second.activate

    assert_load_error(Boto::Templates::DuplicateTemplateError, first.root) { Boto::Templates.fetch(:demo) }
    assert_load_error(Boto::Templates::DuplicateTemplateError, second.root) { Boto::Templates.fetch(:demo) }
  end

  def test_gem_redefining_an_official_template_is_refused_citing_the_gem
    gem = fake_gem("webapi" => DEMO.sub(":demo", ":webapi"))
    gem.activate

    assert_load_error(Boto::Templates::DuplicateTemplateError, "official and cannot be redefined by #{gem.root}") do
      Boto::Templates.fetch(:webapi)
    end
  end

  def test_invalid_template_file_fails_with_its_path
    gem = fake_gem("bad" => "Boto::Template.define(:bad) { |t| t.folder \"lib\" }\n")
    path = File.join(gem.root, "boto", "templates", "bad", "template.rb")
    gem.activate

    assert_load_error(ArgumentError, "#{path}: folder must be one of apps, libs, workers") do
      Boto::Templates.fetch(:bad)
    end
  end

  def test_gem_cannot_declare_legacy_services
    gem = fake_gem("legacy" => "Boto::Template.define(:legacy) { |t| t.folder \"apps\"; t.legacy_services true }\n")
    gem.activate

    assert_load_error(ArgumentError, "legacy_services is internal to boto-rb") { Boto::Templates.fetch(:legacy) }
  end

  def test_failed_load_is_not_cached
    gem = fake_gem("bad" => "Boto::Template.define(:bad) { |t| t.http true }\n")
    gem.activate

    assert_raises(ArgumentError) { Boto::Templates.fetch(:bad) }
    assert_raises(ArgumentError) { Boto::Templates.fetch(:bad) }
  end
end
