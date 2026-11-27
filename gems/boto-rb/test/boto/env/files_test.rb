# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "pathname"
require "tmpdir"

class Boto::Env::FilesTest < Minitest::Test
  ALL_NAMES = %w[.env .env.local .env.development .env.development.local].freeze

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write(name, text)
    File.write(File.join(@dir, name), text)
  end

  def names_for(env_name)
    Boto::Env::Files.for(@dir, env_name:).map { File.basename(_1) }
  end

  def test_lists_all_four_files_in_precedence_order
    ALL_NAMES.each { write(_1, "A=1\n") }
    assert_equal %w[.env.development.local .env.local .env.development .env], names_for("development")
  end

  def test_omits_local_file_in_test
    %w[.env .env.local .env.test .env.test.local].each { write(_1, "A=1\n") }
    assert_equal %w[.env.test.local .env.test .env], names_for("test")
  end

  def test_keeps_local_file_in_development
    write(".env.local", "A=1\n")
    assert_equal [".env.local"], names_for("development")
  end

  def test_skips_missing_files
    write(".env.development", "A=1\n")
    assert_equal [".env.development"], names_for("development")
  end

  def test_returns_absolute_paths
    write(".env", "A=1\n")
    assert(Boto::Env::Files.for(@dir, env_name: "development").all? { Pathname.new(_1).absolute? })
  end

  def test_ignores_directories_named_like_env_files
    Dir.mkdir(File.join(@dir, ".env"))
    assert_empty names_for("development")
  end

  def test_read_gives_the_highest_precedence_file_the_last_word
    write(".env", "A=base\nB=base\nC=base\n")
    write(".env.development", "B=env\nC=env\n")
    write(".env.local", "C=local\n")
    assert_equal({ "A" => "base", "B" => "env", "C" => "local" },
                 Boto::Env::Files.read(@dir, env_name: "development"))
  end

  def test_read_ignores_local_file_in_test
    write(".env", "A=base\n")
    write(".env.local", "A=local\n")
    assert_equal({ "A" => "base" }, Boto::Env::Files.read(@dir, env_name: "test"))
  end

  def test_read_returns_frozen_hash
    write(".env", "A=1\n")
    assert_predicate Boto::Env::Files.read(@dir, env_name: "development"), :frozen?
  end

  def test_read_returns_empty_hash_without_files
    assert_equal({}, Boto::Env::Files.read(@dir, env_name: "development"))
  end

  def test_read_reports_the_file_path_on_parse_error
    write(".env", %(A="abc\n))
    error = assert_raises(Boto::Env::ParseError) { Boto::Env::Files.read(@dir, env_name: "development") }
    assert_includes error.message, File.join(@dir, ".env:1")
  end
end
