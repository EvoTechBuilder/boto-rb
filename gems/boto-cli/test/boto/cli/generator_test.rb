# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Boto::CLI::GeneratorTest < Minitest::Test
  LOCALS = { name: "shop", ruby_version: "4.0.0", boto_version: "0.1.0" }.freeze

  def test_unknown_template_raises
    error = assert_raises(Boto::CLI::Error) { Boto::CLI::Generator.new("does_not_exist") }
    assert_includes error.message, "does_not_exist"
  end

  def test_generates_solution_template
    Dir.mktmpdir do |target|
      files = Boto::CLI::Generator.new("solution").generate(target, LOCALS)

      assert_includes files, ".gitignore"
      assert_includes files, ".ruby-version"
      assert_includes files, "libs/.keep"
      assert_equal "4.0.0", File.read(File.join(target, ".ruby-version")).strip
      assert_includes File.read(File.join(target, "Botofile")), %(solution "shop")
      assert_equal files.sort, files
    end
  end

  def test_gemspec_packages_dotfile_templates
    spec = Gem::Specification.load(File.expand_path("../../../boto-cli.gemspec", __dir__))
    assert_includes spec.files, "templates/solution/.gitignore"
    assert_includes spec.files, "templates/webapi/models/.keep"
  end

  def test_leaves_no_erb_files_behind
    Dir.mktmpdir do |target|
      Boto::CLI::Generator.new("solution").generate(target, LOCALS)
      generated = Dir.glob("**/*", File::FNM_DOTMATCH, base: target)
                     .select { |path| File.file?(File.join(target, path)) }

      refute(generated.any? { |path| path.end_with?(".erb") })
    end
  end
end
