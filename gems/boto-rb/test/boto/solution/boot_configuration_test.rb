# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

class Boto::BootConfigurationTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/environment", __dir__)
  RECORDER = "Boto::BootConfigurationTest::Recorder"

  # Records the lifecycle calls it receives, so a test can tell whether the configuration started it.
  class Recorder < Boto::Plugin
    attr_reader :label, :limit, :events

    def configure(label:, limit: 1)
      @label = label
      @limit = limit
      @events = []
    end

    def start = @events << :start

    def stop = @events << :stop
  end

  def setup
    @root = Dir.mktmpdir("boto-configuration")
    FileUtils.cp_r(File.join(FIXTURE, "."), @root)
    @boots = []
  end

  def teardown
    @boots.each(&:shutdown)
    FileUtils.remove_entry(@root)
  end

  def test_configuration_merges_app_and_environment_plugins
    write("apps/orders/config/app.rb", "Boto.configure { |app| app.use #{RECORDER}, label: \"base\", limit: 5 }")
    write("apps/orders/config/environments/development.rb", "Boto.configure { |app| app.use #{RECORDER}, label: \"dev\" }")

    plugin = recorder(build_boot.configuration("orders", env_name: "development"))

    assert_equal ["dev", 5], [plugin.label, plugin.limit]
  end

  def test_configuration_applies_the_project_env_file
    write("apps/orders/.env", "ORDERS_GREETING=oi\n")

    config = build_boot.configuration("orders", env_name: "development")

    assert_equal "development", config.env_name
    assert_equal "oi", config.env["ORDERS_GREETING"]
  end

  def test_configuration_does_not_start_plugins_or_check_isolation
    write("apps/orders/config/app.rb", "Boto.configure { |app| app.use #{RECORDER}, label: \"base\" }")
    boot = build_boot

    plugin = recorder(boot.configuration("orders", env_name: "production"))

    assert_empty plugin.events
    assert_empty boot.checked_projects
  end

  def test_configuration_refuses_an_invalid_environment_name
    error = assert_raises(Boto::Boot::InvalidEnvironmentError) do
      build_boot.configuration("orders", env_name: "Prod")
    end

    assert_includes error.message, '"Prod"'
  end

  private

  def recorder(config) = config.plugin(:recorder)

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
