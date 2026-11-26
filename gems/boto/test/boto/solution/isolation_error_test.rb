# frozen_string_literal: true

require "test_helper"

class Boto::IsolationErrorTest < Minitest::Test
  Violation = Boto::Isolation::Violation

  def violation(project, path, line, constant, missing_ref)
    Violation.new(project: project, path: path, line: line, constant: constant, missing_ref: missing_ref)
  end

  def test_message_lists_each_project_block_and_one_fix_per_missing_ref
    violations = [
      violation("orders", "services/orders/operations/checkout.rb", 14, "Billing::Invoice", "billing"),
      violation("orders", "services/orders/endpoints/show.rb", 3, "Domain::Customer", "domain"),
      violation("orders", "services/orders/operations/checkout.rb", 20, "Billing::Rate", "billing"),
      violation("billing", "services/billing/models/invoice.rb", 7, "Orders::Order", "orders")
    ]

    expected = <<~MESSAGE.chomp
      project "orders" uses projects it does not reference:
        services/orders/operations/checkout.rb:14  Billing::Invoice  (billing is not in refs)
        services/orders/endpoints/show.rb:3  Domain::Customer  (domain is not in refs)
        services/orders/operations/checkout.rb:20  Billing::Rate  (billing is not in refs)
      Fix: boto ref orders billing
      Fix: boto ref orders domain
      project "billing" uses projects it does not reference:
        services/billing/models/invoice.rb:7  Orders::Order  (orders is not in refs)
      Fix: boto ref billing orders
    MESSAGE

    assert_equal expected, Boto::IsolationError.new(violations).message
  end

  def namespace_violation(project, path, line, constant, namespace)
    Boto::Isolation::NamespaceViolation.new(project: project, path: path, line: line, constant: constant, namespace: namespace)
  end

  def test_message_lists_namespace_violations_in_their_own_block
    violations = [namespace_violation("orders", "services/orders/config/app.rb", 3, "Tokens", "Orders")]

    expected = <<~MESSAGE.chomp
      project "orders" declares constants outside its namespace Orders:
        services/orders/config/app.rb:3  Tokens
      Fix: move them under Orders::
    MESSAGE

    assert_equal expected, Boto::IsolationError.new(violations).message
  end

  def test_message_has_reference_block_then_namespace_block_for_the_same_project
    violations = [
      namespace_violation("orders", "services/orders/config/app.rb", 3, "Tokens", "Orders"),
      violation("orders", "services/orders/operations/a.rb", 1, "Domain::A", "domain")
    ]

    expected = <<~MESSAGE.chomp
      project "orders" uses projects it does not reference:
        services/orders/operations/a.rb:1  Domain::A  (domain is not in refs)
      Fix: boto ref orders domain
      project "orders" declares constants outside its namespace Orders:
        services/orders/config/app.rb:3  Tokens
      Fix: move them under Orders::
    MESSAGE

    assert_equal expected, Boto::IsolationError.new(violations).message
  end

  def test_exposes_violations
    violations = [violation("orders", "services/orders/operations/a.rb", 1, "Domain::A", "domain")]

    error = Boto::IsolationError.new(violations)

    assert_equal violations, error.violations
    assert_kind_of StandardError, error
  end
end
