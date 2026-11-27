# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Boto::CLI::ProjectFolderTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_schema_is_found_by_its_reference
    write("schemas/product_schema.rb")

    assert folder.schema?("product_schema")
    refute folder.schema?("category_schema")
  end

  def test_auth_is_enabled_by_the_plugin_line_in_config
    write("config/app.rb", "Boto.configure do |app|\n  app.use :auth, strategy: :bearer\nend\n")

    assert folder.auth_enabled?
  end

  def test_auth_is_disabled_without_the_plugin_or_the_config_file
    write("config/app.rb", "Boto.configure do |app|\n  app.use :cors\nend\n")
    refute folder.auth_enabled?

    FileUtils.rm_f(File.join(@dir, "config/app.rb"))
    refute folder.auth_enabled?
  end

  def test_same_path_in_another_code_folder_is_a_clash
    write("models/create_product.rb")

    assert_equal "models/create_product.rb", folder.clashing_path(file("operations/create_product.rb"))
  end

  def test_same_path_in_repositories_is_a_clash
    write("repositories/thing_repository.rb")

    assert_equal "repositories/thing_repository.rb", folder.clashing_path(file("operations/thing_repository.rb"))
  end

  def test_same_path_in_the_same_folder_is_not_a_clash
    write("operations/create_product.rb")

    assert_nil folder.clashing_path(file("operations/create_product.rb"))
  end

  def test_test_files_never_clash
    write("models/create_product.rb")

    assert_nil folder.clashing_path(file("test/operations/create_product_test.rb"))
  end

  private

  def folder = Boto::CLI::ProjectFolder.new(@dir)

  def file(path) = Boto::CLI::GeneratedFile.new(path: path, content: "")

  def write(relative, content = "")
    absolute = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, content)
  end
end
