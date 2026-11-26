# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::GraphCommandTest < Minitest::Test
  BOTOFILE = <<~BOTOFILE
    solution "shop"
    project "domain", template: :library
    project "billing", template: :webapi, refs: ["domain", "orders"]
    project "orders", template: :webapi, refs: ["domain"]
  BOTOFILE

  def test_prints_projects_in_topological_order
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, "Botofile"), BOTOFILE)
      out = StringIO.new

      assert_equal 0, graph_command([], out: out, cwd: cwd).call
      assert_equal <<~OUTPUT, out.string
        solution shop
          domain [library]
          orders [webapi]
            -> domain
          billing [webapi]
            -> domain
            -> orders
      OUTPUT
    end
  end

  def test_empty_solution_prints_no_projects
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, "Botofile"), %(solution "shop"\n))
      out = StringIO.new

      assert_equal 0, graph_command([], out: out, cwd: cwd).call
      assert_equal "solution shop\n  (no projects)\n", out.string
    end
  end

  def test_extra_arguments_are_ignored
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, "Botofile"), %(solution "shop"\n))
      out = StringIO.new

      assert_equal 0, graph_command(["extra"], out: out, cwd: cwd).call
      assert_equal "solution shop\n  (no projects)\n", out.string
    end
  end

  def test_missing_botofile_raises
    Dir.mktmpdir do |cwd|
      error = assert_raises(Boto::CLI::Error) { graph_command([], cwd: cwd).call }
      assert_equal "Botofile not found in #{cwd}", error.message
    end
  end

  private

  def graph_command(argv, cwd:, out: StringIO.new)
    Boto::CLI::Commands::Graph.new(argv, out: out, err: StringIO.new, cwd: cwd)
  end
end
