# frozen_string_literal: true

require "test_helper"

class Boto::Isolation::ScannerTest < Minitest::Test
  Scanner = Boto::Isolation::Scanner
  Use = Boto::Isolation::Scanner::Use

  def scan(source)
    Scanner.scan(source, path: "file.rb")
  end

  def test_simple_constant_is_a_use
    assert_equal [Use.new(constant: "Billing", root: "Billing", line: 1)], scan("Billing").used
  end

  def test_nested_path_is_a_single_use
    assert_equal [Use.new(constant: "A::B::C", root: "A", line: 1)], scan("A::B::C").used
  end

  def test_top_level_path_uses_its_first_segment_as_root
    assert_equal [Use.new(constant: "Billing::X", root: "Billing", line: 1)], scan("::Billing::X").used
  end

  def test_use_inside_nested_class_and_module_has_its_line
    source = <<~RUBY
      module Orders
        class Show
          def call
            Billing::Invoice
          end
        end
      end
    RUBY

    assert_equal [Use.new(constant: "Orders", root: "Orders", line: 1), Use.new(constant: "Billing::Invoice", root: "Billing", line: 4)],
                 scan(source).used
  end

  def test_superclass_is_a_use
    assert_includes scan("module Orders\n  class Show < Billing::Base; end\nend\n").used.map(&:constant), "Billing::Base"
  end

  def test_top_level_declaration_uses_its_root_and_declares_the_rest
    scan_result = scan("class Orders::Users::Show; end\nmodule Admin::Tools; end")

    assert_equal %w[Orders Admin], scan_result.used.map(&:constant)
    assert_equal Set["Users", "Show", "Tools"], scan_result.declared
  end

  def test_nested_declarations_declare_every_segment
    scan_result = scan("module Orders\n  module Billing\n    class Invoice; end\n  end\nend\n")

    assert_equal %w[Orders], scan_result.used.map(&:constant)
    assert_equal Set["Billing", "Invoice"], scan_result.declared
  end

  def test_constant_assignment_is_a_declaration
    scan_result = scan("FOO = 1")

    assert_empty scan_result.used
    assert_equal Set["FOO"], scan_result.declared
  end

  def test_constant_path_assignment_declares_last_segment_and_keeps_prefix_as_use
    scan_result = scan("Billing::RATE = 1")

    assert_equal Set["RATE"], scan_result.declared
    assert_equal ["Billing"], scan_result.used.map(&:constant)
  end

  def test_dynamic_path_parent_does_not_produce_a_use_for_its_last_segment
    assert_empty scan("self.class::Foo").used
  end

  def test_strings_and_comments_are_not_uses
    source = <<~RUBY
      message = "Billing::Invoice"
      # Billing::Invoice
    RUBY

    assert_empty scan(source).used
  end

  def test_syntax_error_raises_with_path_and_line
    error = assert_raises(Scanner::SyntaxError) do
      Scanner.scan("x = 1\ndef broken(", path: "services/orders/broken.rb")
    end

    assert_equal "services/orders/broken.rb", error.path
    assert_equal 2, error.line
    assert_match(/\Aservices\/orders\/broken\.rb:2: /, error.message)
  end
end
