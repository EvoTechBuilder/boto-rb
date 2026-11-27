# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Boto::CLI::GeneratorTest < Minitest::Test
  LOCALS = { name: "shop", ruby_version: "4.0.0", boto_version: "0.1.0" }.freeze

  def test_missing_folder_raises
    error = assert_raises(Boto::CLI::Error) { Boto::CLI::Generator.new("does_not_exist") }
    assert_includes error.message, "does_not_exist"
  end

  def test_generates_solution_template
    Dir.mktmpdir do |target|
      files = solution_generator.generate(target, LOCALS)

      assert_includes files, ".gitignore"
      assert_includes files, ".ruby-version"
      assert_equal %w[.gitignore .ruby-version Botofile Gemfile], files.sort
      assert_equal "4.0.0", File.read(File.join(target, ".ruby-version")).strip
      assert_includes File.read(File.join(target, "Botofile")), %(solution "shop")
      assert_equal files.sort, files
    end
  end

  def test_gemspec_packages_dotfile_templates
    spec = Gem::Specification.load(File.expand_path("../../../../boto-rb-cli.gemspec", __dir__))
    assert_includes spec.files, "templates/solution/.gitignore"
    assert_includes spec.files, "templates/webapi/models/.keep"
  end

  def test_leaves_no_erb_files_behind
    Dir.mktmpdir do |target|
      solution_generator.generate(target, LOCALS)
      generated = Dir.glob("**/*", File::FNM_DOTMATCH, base: target)
                     .select { |path| File.file?(File.join(target, path)) }

      refute(generated.any? { |path| path.end_with?(".erb") })
    end
  end

  def test_renders_erb_files_from_a_source_folder
    Dir.mktmpdir do |source|
      File.write(File.join(source, "config.rb.erb"), "ns = <%= namespace %>, refs = <%= refs.inspect %>")
      Dir.mktmpdir do |target|
        files = Boto::CLI::Generator.new(source).generate(target, namespace: "Shop", refs: %w[dominio])

        assert_equal %w[config.rb], files
        assert_equal %(ns = Shop, refs = ["dominio"]), File.read(File.join(target, "config.rb"))
      end
    end
  end

  def test_inside_accepts_paths_under_the_folder_only
    assert Boto::CLI::Generator.inside?("/a/b/apps/x/file.rb", "/a/b/apps/x")
    refute Boto::CLI::Generator.inside?("/a/b/apps/x/../../evil.rb", "/a/b/apps/x")
    refute Boto::CLI::Generator.inside?("/a/b/apps/xy/file.rb", "/a/b/apps/x")
  end

  private

  def solution_generator
    Boto::CLI::Generator.new(Boto::CLI::Generator.official_dir("solution"))
  end
end
