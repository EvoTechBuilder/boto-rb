# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"
require "support/fake_template_gem"

# A template with mounts_refs true gets the apps of its HTTP refs in the same process.
class Boto::BootGatewayTest < Minitest::Test
  GATEWAY_SOURCE = <<~RUBY
    Boto::Template.define :gateway do |t|
      t.folder "apps"
      t.http true
      t.mounts_refs true
    end
  RUBY

  ENV_NAME = "test"

  def setup
    @template_gem = FakeTemplateGem.new
    @template_gem.write("gateway", GATEWAY_SOURCE)
    @template_gem.activate
    @root = Dir.mktmpdir("boto-gateway")
    FileUtils.mkdir_p(%w[apps libs].map { File.join(@root, _1) })
    write("apps/catalogo/config/app.rb", "Boto.configure { |app| }\n")
    write("apps/pedidos/config/app.rb", "Boto.configure { |app| }\n")
    write("libs/dominio/config/app.rb", "Boto.configure { |app| }\n")
  end

  def teardown
    @boot&.shutdown
    @template_gem.cleanup
    FileUtils.remove_entry(@root)
  end

  def test_gateway_app_carries_the_apps_of_its_http_refs
    boot_with_refs(%w[catalogo pedidos])
    app = @boot.app("borda", env_name: ENV_NAME)

    assert_equal %w[catalogo pedidos], app.services.keys
    assert(app.services.values.all? { _1.is_a?(Boto::App) })
  end

  def test_app_of_a_ref_is_not_mounted_twice
    boot_with_refs(%w[catalogo])
    app = @boot.app("borda", env_name: ENV_NAME)

    assert_same app.services["catalogo"], @boot.app("catalogo", env_name: ENV_NAME)
  end

  def test_ref_to_a_non_http_project_is_a_boot_error
    boot_with_refs(%w[dominio])

    error = assert_raises(Boto::App::BootError) { @boot.app("borda", env_name: ENV_NAME) }
    assert_equal 'gateway borda: ref "dominio" is not an HTTP project', error.message
  end

  private

  def boot_with_refs(refs)
    write("Botofile", <<~BOTOFILE)
      solution "shop"
      project "catalogo", template: :webapi
      project "pedidos", template: :webapi
      project "dominio", template: :library
      project "borda", template: :gateway, refs: #{refs.inspect}
    BOTOFILE
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(@root, "Botofile")), root: @root, env: {},
                                                                              warn_output: StringIO.new)
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
end
