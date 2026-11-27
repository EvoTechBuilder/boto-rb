# frozen_string_literal: true

require "test_helper"

class Boto::TemplateTest < Minitest::Test
  def assert_invalid(reason, &block)
    error = assert_raises(ArgumentError) { Boto::Template.define(:demo, &block) }
    assert_equal "#{__FILE__}: #{reason}", error.message
  end

  def test_folder_must_be_a_solution_folder
    assert_invalid(%(folder must be one of apps, libs, workers, got "lib")) { |t| t.folder "lib" }
  end

  def test_folder_is_required
    assert_invalid("folder is required") { |t| t.http true }
  end

  def test_http_must_be_boolean
    assert_invalid(%(http must be true or false, got "sim")) { |t| t.folder "apps"; t.http "sim" }
  end

  def test_files_must_be_an_existing_directory
    assert_invalid(%(files must be an existing directory, got "/nope/missing")) do |t|
      t.folder "apps"
      t.files "/nope/missing"
    end
  end

  def test_summary_must_be_a_string
    assert_invalid "summary must be a String, got 1" do |t|
      t.folder "apps"
      t.summary 1
    end
  end

  def test_name_must_be_a_lowercase_identifier
    error = assert_raises(ArgumentError) { Boto::Template.define("Bad Name") { |t| t.folder "apps" } }
    assert_equal %(#{__FILE__}: name "Bad Name" must match \\A[a-z][a-z0-9_]*\\z), error.message
  end

  def test_unknown_option_names_the_option
    assert_invalid "unknown option color" do |t|
      t.folder "apps"
      t.color "red"
    end
  end

  def test_legacy_services_is_internal_to_boto_rb
    assert_invalid "legacy_services is internal to boto-rb" do |t|
      t.folder "apps"
      t.legacy_services true
    end
  end

  def test_declaring_outside_the_registry_load_is_refused
    assert_raises(Boto::Templates::ClosedRegistryError) do
      Boto::Template.define(:demo) { |t| t.folder "apps" }
    end
  end

  def test_official_source_is_boto_rb
    path = File.join(Boto::Template::OFFICIAL_DIR, "webapi", "template.rb")

    assert_equal "boto-rb", Boto::Template.source_for(path)
  end

  def test_gem_source_is_the_root_holding_boto_dir
    assert_equal "/opt/vendor/demo", Boto::Template.source_for("/opt/vendor/demo/boto/templates/demo/template.rb")
  end

  def test_mounts_refs_defaults_to_false
    assert_equal false, built_template.mounts_refs
  end

  def test_mounts_refs_can_be_enabled
    assert_equal true, built_template(mounts_refs: true).mounts_refs
  end

  def test_mounts_refs_must_be_boolean
    assert_invalid(%(mounts_refs must be true or false, got "sim")) { |t| t.folder "apps"; t.mounts_refs "sim" }
  end

  private

  def built_template(**options)
    builder = Boto::Template::Builder.new(name: :gateway, path: "gateway/template.rb", source: "test", official: false)
    builder.folder("apps")
    options.each { |option, value| builder.public_send(option, value) }
    builder.to_template
  end
end
