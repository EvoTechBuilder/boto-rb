# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class Boto::IsolationTest < Minitest::Test
  Violation = Boto::Isolation::Violation
  NamespaceViolation = Boto::Isolation::NamespaceViolation
  CHECKOUT = "apps/orders/operations/checkout.rb"

  SOURCE = <<~BOTO
    solution "shop"
    project "domain", template: :library
    project "billing", template: :webapi, refs: %w[domain]
    project "orders", template: :webapi, refs: %w[billing]
  BOTO

  def with_solution(files)
    Dir.mktmpdir do |root|
      files.each { |path, body| write(root, path, body) }
      yield Boto::Botofile.parse(SOURCE), root
    end
  end

  def write(root, path, body)
    full_path = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, body)
  end

  def check(files, **options)
    with_solution(files) { |solution, root| Boto::Isolation.check(solution, root: root, **options) }
  end

  def test_use_of_direct_reference_and_own_namespace_is_allowed
    files = { CHECKOUT => "Billing::Invoice.new\nOrders::Order.new\n" }

    assert_empty check(files)
  end

  def test_use_of_transitive_reference_is_a_violation
    violations = check({ CHECKOUT => "x = 1\nDomain::Customer.find\n" })

    assert_equal [Violation.new(project: "orders", path: CHECKOUT, line: 2,
                                constant: "Domain::Customer", missing_ref: "domain")],
                 violations
  end

  def test_project_without_refs_using_another_is_a_violation
    violations = check({ "libs/domain/models/order.rb" => "Billing::Invoice\n" })

    assert_equal [Violation.new(project: "domain", path: "libs/domain/models/order.rb", line: 1,
                                constant: "Billing::Invoice", missing_ref: "billing")],
                 violations
  end

  def test_external_constants_are_never_violations
    files = { CHECKOUT => "JSON.parse(x)\nBoto::Endpoint\nRack::Request\n" }

    assert_empty check(files)
  end

  def test_locally_declared_namespace_is_not_a_violation
    source = "module Orders\n  module Billing\n  end\n\n  Billing::X\nend\n"

    assert_empty check({ CHECKOUT => source })
  end

  def test_reopening_another_projects_namespace_is_a_violation
    source = "class Billing::Invoice\n  def total = 0\nend\n\nBilling::Report\n"
    violations = check({ "apps/orders/models/invoice_patch.rb" => source }, projects: ["domain"])

    assert_empty violations
    domain_violations = check({ "libs/domain/models/invoice_patch.rb" => source }).grep(Violation)

    assert_equal [%w[Billing billing], %w[Billing::Report billing]], domain_violations.map { [_1.constant, _1.missing_ref] }
  end

  def test_top_level_class_in_config_is_a_namespace_violation
    violations = check({ "apps/orders/config/app.rb" => "\nclass Tokens; end\n" })

    assert_equal [NamespaceViolation.new(project: "orders", path: "apps/orders/config/app.rb", line: 2,
                                         constant: "Tokens", namespace: "Orders")],
                 violations
  end

  def test_top_level_constant_in_operations_is_a_namespace_violation
    violations = check({ CHECKOUT => "TOKENS = 1\n" })

    assert_equal %w[TOKENS], violations.map(&:constant)
    assert_kind_of NamespaceViolation, violations.first
  end

  def test_declarations_under_own_namespace_are_not_namespace_violations
    source = "module Orders\n  LIMIT = 1\nend\n\nclass Orders::X; end\n"

    assert_empty check({ CHECKOUT => source })
  end

  def test_test_files_may_declare_prefixed_top_level_constants
    source = "class OrdersHealthTest < Minitest::Test; end\n"

    assert_empty check({ "apps/orders/test/x_test.rb" => source })
  end

  def test_reference_and_namespace_violations_are_sorted_together
    files = {
      CHECKOUT => "Domain::Customer\nTOKENS = 1\n",
      "apps/orders/config/app.rb" => "class Tokens; end\n"
    }

    assert_equal [
      ["apps/orders/config/app.rb", 1],
      [CHECKOUT, 1],
      [CHECKOUT, 2]
    ], check(files).map { [_1.path, _1.line] }
  end

  def test_files_under_test_are_read
    violations = check({ "apps/orders/test/checkout_test.rb" => "Domain::Customer\n" })

    assert_equal ["apps/orders/test/checkout_test.rb"], violations.map(&:path)
  end

  def test_projects_option_filters_the_result
    files = { CHECKOUT => "Domain::Customer\n", "libs/domain/models/x.rb" => "Billing::X\n" }

    violations = check(files, projects: ["orders"])

    assert_equal %w[orders], violations.map(&:project)
  end

  def test_unknown_project_in_projects_option_raises_key_error
    assert_raises(KeyError) { check({}, projects: ["ghost"]) }
  end

  def test_violations_are_sorted_by_project_path_and_line
    files = {
      "apps/orders/operations/b.rb" => "\nDomain::A\n",
      "apps/orders/operations/a.rb" => "Domain::B\nDomain::C\n",
      "libs/domain/models/x.rb" => "Billing::X\n"
    }

    keys = check(files).map { [_1.project, _1.path, _1.line] }

    assert_equal [
      ["domain", "libs/domain/models/x.rb", 1],
      ["orders", "apps/orders/operations/a.rb", 1],
      ["orders", "apps/orders/operations/a.rb", 2],
      ["orders", "apps/orders/operations/b.rb", 2]
    ], keys
  end

  def test_project_without_source_dirs_has_no_violations
    assert_empty check({})
  end

  def test_syntax_error_in_project_file_propagates
    assert_raises(Boto::Isolation::Scanner::SyntaxError) { check({ CHECKOUT => "def broken(" }) }
  end
end
