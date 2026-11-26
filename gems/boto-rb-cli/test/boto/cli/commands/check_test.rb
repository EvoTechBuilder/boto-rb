# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::CheckCommandTest < Minitest::Test
  BOTOFILE = <<~BOTOFILE
    solution "shop"
    project "domain", template: :library
    project "billing", template: :webapi, refs: ["domain"]
    project "orders", template: :webapi, refs: ["billing"]
  BOTOFILE
  DOMAIN_SOURCE = <<~RUBY
    module Domain
      class Customer; end
    end
  RUBY
  BILLING_SOURCE = <<~RUBY
    class Billing::Invoice
      def customer = Domain::Customer
    end
  RUBY
  ORDERS_SOURCE = <<~RUBY
    class Orders::Order
      def invoice = Billing::Invoice
    end
  RUBY
  ORDERS_VIOLATION_SOURCE = <<~RUBY
    class Orders::Order
      def customer = Domain::Customer
    end
  RUBY
  ORDERS_PATH = "services/orders/endpoints/order.rb"

  def test_clean_solution_succeeds
    Dir.mktmpdir do |cwd|
      write_solution(cwd)
      out = StringIO.new
      err = StringIO.new

      assert_equal 0, check_command([], cwd: cwd, out: out, err: err).call
      assert_equal "No isolation violations in 3 projects\n", out.string
      assert_empty err.string
    end
  end

  def test_violation_reports_path_constant_and_fix
    Dir.mktmpdir do |cwd|
      write_solution(cwd, orders: ORDERS_VIOLATION_SOURCE)
      out = StringIO.new
      err = StringIO.new

      assert_equal 1, check_command([], cwd: cwd, out: out, err: err).call
      assert_empty out.string
      assert_includes err.string, ORDERS_PATH
      assert_includes err.string, "Domain::Customer"
      assert_includes err.string, "Fix: boto ref orders domain"
    end
  end

  def test_project_argument_limits_the_check
    Dir.mktmpdir do |cwd|
      write_solution(cwd, orders: ORDERS_VIOLATION_SOURCE)
      out = StringIO.new
      err = StringIO.new

      assert_equal 0, check_command(["billing"], cwd: cwd, out: out, err: err).call
      assert_equal "No isolation violations in 1 project\n", out.string
      assert_empty err.string
    end
  end

  def test_unknown_project_raises
    Dir.mktmpdir do |cwd|
      write_solution(cwd)

      error = assert_raises(Boto::CLI::Error) { check_command(["nope"], cwd: cwd).call }
      assert_equal %(unknown project "nope"), error.message
    end
  end

  def test_extra_arguments_raise_usage
    Dir.mktmpdir do |cwd|
      write_solution(cwd)

      error = assert_raises(Boto::CLI::Error) { check_command(%w[billing orders], cwd: cwd).call }
      assert_equal "Usage: boto check [project]", error.message
    end
  end

  def test_missing_botofile_raises
    Dir.mktmpdir do |cwd|
      error = assert_raises(Boto::CLI::Error) { check_command([], cwd: cwd).call }
      assert_equal "Botofile not found in #{cwd}", error.message
    end
  end

  def test_help_lists_check
    Dir.mktmpdir do |cwd|
      out = StringIO.new

      assert_equal 0, Boto::CLI::Runner.new(out: out, err: StringIO.new, cwd: cwd).run(["help"])
      assert_match(/^  check +#{Regexp.escape(Boto::CLI::Commands::Check::SUMMARY)}$/, out.string)
    end
  end

  private

  def write_solution(cwd, orders: ORDERS_SOURCE)
    write(cwd, "Botofile", BOTOFILE)
    write(cwd, "libs/domain/endpoints/customer.rb", DOMAIN_SOURCE)
    write(cwd, "services/billing/endpoints/invoice.rb", BILLING_SOURCE)
    write(cwd, ORDERS_PATH, orders)
  end

  def write(cwd, relative_path, content)
    path = File.join(cwd, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def check_command(argv, cwd:, out: StringIO.new, err: StringIO.new)
    Boto::CLI::Commands::Check.new(argv, out: out, err: err, cwd: cwd)
  end
end
