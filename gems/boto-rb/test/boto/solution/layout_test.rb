# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class Boto::LayoutTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("boto-layout")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def project(name, template: :webapi)
    Boto::Project.new(name: name, template: template, refs: [], line: 1)
  end

  def solution(*projects)
    Boto::Solution.new(name: "loja", projects: projects)
  end

  def make_dir(*parts)
    FileUtils.mkdir_p(File.join(@root, *parts))
  end

  def test_passes_without_legacy_directories
    make_dir("apps", "pedidos")

    assert_nil Boto::Layout.check!(solution(project("pedidos")), root: @root)
  end

  def test_raises_when_http_project_is_still_in_services
    make_dir("services", "pedidos")

    error = assert_raises(Boto::LegacyLayoutError) do
      Boto::Layout.check!(solution(project("pedidos")), root: @root)
    end

    assert_equal <<~MESSAGE.chomp, error.message
      project "pedidos" is in services/pedidos; HTTP projects now live in apps/pedidos.
      Fix: git mv services/pedidos apps/pedidos
    MESSAGE
  end

  def test_raises_one_block_per_legacy_project
    make_dir("services", "pedidos")
    make_dir("services", "api")

    error = assert_raises(Boto::LegacyLayoutError) do
      Boto::Layout.check!(solution(project("pedidos"), project("api", template: :microservice)), root: @root)
    end

    assert_equal %w[pedidos api], error.projects
    assert_equal <<~MESSAGE.chomp, error.message
      project "pedidos" is in services/pedidos; HTTP projects now live in apps/pedidos.
      Fix: git mv services/pedidos apps/pedidos
      project "api" is in services/api; HTTP projects now live in apps/api.
      Fix: git mv services/api apps/api
    MESSAGE
  end

  def test_passes_when_both_directories_exist
    make_dir("services", "pedidos")
    make_dir("apps", "pedidos")

    assert_nil Boto::Layout.check!(solution(project("pedidos")), root: @root)
  end

  def test_library_in_libs_is_never_legacy
    make_dir("libs", "dominio")
    make_dir("services", "dominio")

    assert_nil Boto::Layout.check!(solution(project("dominio", template: :library)), root: @root)
  end
end
