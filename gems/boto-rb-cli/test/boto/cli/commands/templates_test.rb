# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::TemplatesCommandTest < Minitest::Test
  COMMAND = Boto::CLI::Commands::Templates
  GEMFILE = "Gemfile"
  NEW_GEM = "boto-rb-graphql"
  DEMO_SOURCE = <<~RUBY
    Boto::Template.define :demo do |t|
      t.folder "apps"
      t.http true
      t.files File.join(__dir__, "files")
    end
  RUBY

  def setup
    Boto::Templates.reset!
    @cwd = Dir.mktmpdir
    @official_root = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@official_root, "library"))
    @gem_root = nil
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    $LOAD_PATH.delete(@gem_root) if @gem_root
    Boto::Templates.reset!
    [@cwd, @official_root, @gem_root].compact.each { FileUtils.remove_entry(_1) }
  end

  def test_list_outside_a_solution_shows_official_templates_with_their_origin
    assert_equal 0, command(%w[list]).call
    assert_match(%r{^library\s+libs/\s+\(boto-rb\)$}, @out.string)
    assert_match(%r{^webapi\s+apps/\s+http\s+\(boto-rb, not available yet\)$}, @out.string)
  end

  def test_list_shows_gem_templates_with_http
    activate_fake_gem
    assert_equal 0, command(%w[list]).call

    demo_line = @out.string.lines.find { _1.start_with?("demo") }
    assert_match(%r{^demo\s+apps/\s+http\s+\(}, demo_line)
    refute_includes demo_line, "not available"
  end

  def test_install_appends_the_gem_line
    write_gemfile(%(source "https://rubygems.org"\n))

    assert_equal 0, command(["install", NEW_GEM]).call
    assert_equal %(source "https://rubygems.org"\ngem "#{NEW_GEM}"\n), read_gemfile
    assert_equal "update Gemfile\nNext: bundle install\nThen: boto templates list\n", @out.string
  end

  def test_install_breaks_the_line_when_gemfile_lacks_a_final_newline
    write_gemfile(%(source "https://rubygems.org"))

    command(["install", NEW_GEM]).call
    assert_equal %(source "https://rubygems.org"\ngem "#{NEW_GEM}"\n), read_gemfile
  end

  def test_install_twice_is_an_error
    write_gemfile("")
    command(["install", NEW_GEM]).call

    error = assert_raises(Boto::CLI::Error) { command(["install", NEW_GEM]).call }
    assert_equal "#{NEW_GEM} is already in the Gemfile", error.message
  end

  def test_install_recognizes_gems_declared_with_other_quotes_and_options
    write_gemfile(%(  gem '#{NEW_GEM}', "~> 1.0"\n))

    error = assert_raises(Boto::CLI::Error) { command(["install", NEW_GEM]).call }
    assert_equal "#{NEW_GEM} is already in the Gemfile", error.message
  end

  def test_install_rejects_invalid_gem_names
    write_gemfile("")
    ["Boto", "../x", "-x", "a b"].each do |name|
      error = assert_raises(Boto::CLI::Error) { command(["install", name]).call }
      assert_equal %(invalid gem name "#{name}"), error.message
    end
    assert_equal "", read_gemfile
  end

  def test_install_outside_a_solution_is_an_error
    error = assert_raises(Boto::CLI::Error) { command(["install", NEW_GEM]).call }
    assert_equal "Gemfile not found in #{@cwd}", error.message
  end

  def test_no_subcommand_or_unknown_subcommand_shows_usage
    [[], %w[remove demo], %w[list extra], %w[install]].each do |argv|
      error = assert_raises(Boto::CLI::Error) { command(argv).call }
      assert_equal COMMAND::USAGE, error.message, argv.inspect
    end
  end

  private

  def command(argv)
    COMMAND.new(argv, out: @out, err: @err, cwd: @cwd, official_root: @official_root)
  end

  def write_gemfile(content)
    File.write(File.join(@cwd, GEMFILE), content)
  end

  def read_gemfile = File.read(File.join(@cwd, GEMFILE))

  # A gem-shaped directory on $LOAD_PATH with one declared template, as an installed template gem would have.
  def activate_fake_gem
    @gem_root = File.realpath(Dir.mktmpdir)
    dir = File.join(@gem_root, "boto", "templates", "demo")
    FileUtils.mkdir_p(File.join(dir, "files"))
    File.write(File.join(dir, "template.rb"), DEMO_SOURCE)
    $LOAD_PATH.unshift(@gem_root)
    Boto::Templates.reset!
  end
end
