# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::RefCommandTest < Minitest::Test
  BOTOFILE = <<~BOTOFILE
    solution "shop"
    project "domain", template: :library
    project "orders", template: :webapi
  BOTOFILE

  def test_adds_reference_and_writes_file
    in_solution do |cwd|
      out = StringIO.new
      assert_equal 0, ref_command(["orders", "domain"], out: out, cwd: cwd).call

      assert_equal "orders -> domain\n", out.string
      assert_equal ["domain"], Boto::Botofile.load(botofile_path(cwd)).project("orders").refs
    end
  end

  def test_cycle_raises_and_keeps_file
    in_solution do |cwd|
      ref_command(["orders", "domain"], cwd: cwd).call
      before = File.read(botofile_path(cwd))

      assert_raises(Boto::Botofile::InvalidError) { ref_command(["domain", "orders"], cwd: cwd).call }
      assert_equal before, File.read(botofile_path(cwd))
    end
  end

  def test_unknown_project_raises_and_keeps_file
    in_solution do |cwd|
      assert_raises(Boto::Botofile::InvalidError) { ref_command(["orders", "ghost"], cwd: cwd).call }
      assert_equal BOTOFILE, File.read(botofile_path(cwd))
    end
  end

  def test_missing_arguments_raises_usage
    in_solution do |cwd|
      error = assert_raises(Boto::CLI::Error) { ref_command(["orders"], cwd: cwd).call }
      assert_equal "usage: boto ref <project> <reference>", error.message
    end
  end

  def test_missing_botofile_raises
    Dir.mktmpdir do |cwd|
      error = assert_raises(Boto::CLI::Error) { ref_command(["orders", "domain"], cwd: cwd).call }
      assert_equal "Botofile not found in #{cwd}", error.message
    end
  end

  def test_rejects_reference_with_invalid_name
    error = assert_raises(Boto::CLI::Error) do
      Boto::CLI::Commands::Ref.new(["orders", "a b"], out: StringIO.new, err: StringIO.new, cwd: Dir.pwd).call
    end
    assert_includes error.message, "invalid reference"
  end

  private

  def in_solution
    Dir.mktmpdir do |cwd|
      File.write(botofile_path(cwd), BOTOFILE)
      yield cwd
    end
  end

  def botofile_path(cwd)
    File.join(cwd, "Botofile")
  end

  def ref_command(argv, cwd:, out: StringIO.new)
    Boto::CLI::Commands::Ref.new(argv, out: out, err: StringIO.new, cwd: cwd)
  end
end
