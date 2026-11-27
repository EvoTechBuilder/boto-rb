# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "../../fixtures/boot_test_plugins"

class Boto::BootEnvironmentTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/environment", __dir__)
  LABELED = "Boto::BootEnvironmentTest::Labeled"

  # Records the label and limit it was declared with, so a test can see which config file won.
  class Labeled < Boto::Plugin
    attr_reader :label, :limit

    def configure(label:, limit: 1)
      @label = label
      @limit = limit
    end
  end

  def setup
    @root = Dir.mktmpdir("boto-environment")
    FileUtils.cp_r(File.join(FIXTURE, "."), @root)
    @boots = []
  end

  def teardown
    @boots.each(&:shutdown)
    FileUtils.remove_entry(@root)
  end

  def test_environment_file_is_read_only_in_its_environment
    write("apps/orders/config/app.rb", "Boto.configure { |app| app.use #{LABELED}, label: \"base\" }")
    write("apps/orders/config/environments/development.rb", "Boto.configure { |app| app.use #{LABELED}, label: \"dev\" }")
    boot = build_boot

    assert_equal "dev", labeled(boot.app("orders", env_name: "development")).label
    assert_equal "base", labeled(boot.app("orders", env_name: "production")).label
  end

  def test_environment_without_file_uses_only_the_general_config
    write("apps/orders/config/app.rb", "Boto.configure { |app| app.use #{LABELED}, label: \"base\" }")

    assert_equal "base", labeled(build_boot.app("orders", env_name: "staging")).label
  end

  def test_environment_file_merges_options_into_a_plugin_declared_in_app_rb
    write("apps/orders/config/app.rb", "Boto.configure { |app| app.use #{LABELED}, label: \"base\", limit: 5 }")
    write("apps/orders/config/environments/development.rb", "Boto.configure { |app| app.use #{LABELED}, label: \"dev\" }")

    plugin = labeled(build_boot.app("orders", env_name: "development"))

    assert_equal ["dev", 5], [plugin.label, plugin.limit]
  end

  def test_environment_file_adds_a_plugin_that_app_rb_does_not_declare
    write("apps/orders/config/environments/development.rb", "Boto.configure { |app| app.use BootTestPlugins::Stamp }")
    boot = build_boot

    assert_includes boot.app("orders", env_name: "development").plugins.map { _1.class.plugin_name }, :stamp
    refute_includes boot.app("orders", env_name: "production").plugins.map { _1.class.plugin_name }, :stamp
  end

  def test_boto_env_selects_the_environment_file
    write("apps/orders/config/environments/development.rb", "Boto.configure { |app| app.use #{LABELED}, label: \"dev\" }")

    assert_equal "dev", labeled(build_boot(env: { "BOTO_ENV" => "development" }).app("orders")).label
  end

  def test_invalid_environment_name_is_refused
    ["../x", "Prod", "9dev", ""].each do |name|
      error = assert_raises(Boto::Boot::InvalidEnvironmentError) { build_boot.app("orders", env_name: name) }
      assert_includes error.message, name.inspect
    end
  end

  def test_invalid_boto_env_is_refused
    error = assert_raises(Boto::Boot::InvalidEnvironmentError) do
      build_boot(env: { "BOTO_ENV" => "Prod" }).app("orders")
    end

    assert_includes error.message, '"Prod"'
  end

  private

  def labeled(app) = app.plugins.find { _1.is_a?(Labeled) }

  def build_boot(env: {})
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@root, "Botofile")), root: @root,
                                                                            env: env, warn_output: StringIO.new)
    @boots << boot
    boot
  end

  def write(relative_path, content)
    path = File.join(@root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
