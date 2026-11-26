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

  def test_exposes_violations
    violations = [violation("orders", "services/orders/operations/a.rb", 1, "Domain::A", "domain")]

    error = Boto::IsolationError.new(violations)

    assert_equal violations, error.violations
    assert_kind_of StandardError, error
  end
end
