# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Boto::CLI::GeneratedFileTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_target_resolves_inside_the_project_folder
    file = Boto::CLI::GeneratedFile.new(path: "schemas/product_schema.rb", content: "")

    assert_equal File.join(File.expand_path(@dir), "schemas/product_schema.rb"), file.target(@dir)
  end

  def test_target_refuses_a_path_that_leaves_the_folder
    file = Boto::CLI::GeneratedFile.new(path: "../escape.rb", content: "")

    error = assert_raises(Boto::CLI::Error) { file.target(@dir) }
    assert_equal %(path "../escape.rb" leaves the project folder), error.message
  end

  def test_write_creates_the_folders_and_the_file
    file = Boto::CLI::GeneratedFile.new(path: "models/orders/item.rb", content: "x\n")

    file.write(@dir)

    assert_equal "x\n", File.read(File.join(@dir, "models/orders/item.rb"))
    assert file.exist?(@dir)
  end
end
