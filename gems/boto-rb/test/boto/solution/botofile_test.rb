# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Boto::BotofileTest < Minitest::Test
  VALID = <<~BOTO
    solution "shop"

    project "domain", template: :library
    project "orders", template: :webapi, refs: %w[domain]
  BOTO

  def assert_invalid(expected, source)
    error = assert_raises(Boto::Botofile::InvalidError) { Boto::Botofile.parse(source) }
    assert_equal expected, error.message
  end

  def test_invalid_solution_name
    assert_invalid %(Botofile:1: invalid solution name "My Shop"), %(solution "My Shop")
  end

  def test_parses_valid_dsl_into_solution
    solution = Boto::Botofile.parse(VALID)

    assert_equal "shop", solution.name
    assert_equal %w[domain orders], solution.projects.map(&:name)
    assert_equal "services/orders", solution.project("orders").path
    assert_equal %w[domain], solution.project("orders").refs
  end

  def test_project_line_is_captured
    assert_equal 4, Boto::Botofile.parse(VALID).project("orders").line
  end

  def test_refs_are_frozen_strings_accepting_symbols
    source = <<~BOTO
      solution "shop"
      project "domain", template: :library
      project "orders", template: :webapi, refs: [:domain]
    BOTO
    refs = Boto::Botofile.parse(source).project("orders").refs

    assert_equal %w[domain], refs
    assert_predicate refs, :frozen?
    assert_predicate refs.first, :frozen?
  end

  def test_missing_solution_has_no_line
    assert_invalid "Botofile: solution name is missing", <<~BOTO
      project "domain", template: :library
    BOTO
  end

  def test_solution_declared_twice_reports_line
    assert_invalid "Botofile:2: solution declared twice", <<~BOTO
      solution "shop"
      solution "other"
    BOTO
  end

  def test_invalid_project_name_reports_line
    assert_invalid %(Botofile:2: invalid project name "Orders"), <<~BOTO
      solution "shop"
      project "Orders", template: :library
    BOTO
  end

  def test_duplicate_project_name_reports_second_declaration_line
    assert_invalid %(Botofile:3: duplicate project "domain"), <<~BOTO
      solution "shop"
      project "domain", template: :library
      project "domain", template: :library
    BOTO
  end

  def test_same_namespace_with_extra_underscores_reports_second_declaration_line
    assert_invalid %(Botofile:3: project "foo__bar" has the same namespace FooBar as project "foo_bar"), <<~BOTO
      solution "shop"
      project "foo_bar", template: :library
      project "foo__bar", template: :library
    BOTO
  end

  def test_same_namespace_with_trailing_underscore_is_refused
    assert_invalid %(Botofile:3: project "foo_bar_" has the same namespace FooBar as project "foo_bar"), <<~BOTO
      solution "shop"
      project "foo_bar", template: :library
      project "foo_bar_", template: :library
    BOTO
  end

  def test_same_namespace_with_digit_after_underscore_is_refused
    assert_invalid %(Botofile:3: project "foo1bar" has the same namespace Foo1bar as project "foo_1bar"), <<~BOTO
      solution "shop"
      project "foo_1bar", template: :library
      project "foo1bar", template: :library
    BOTO
  end

  def test_different_namespaces_differing_only_in_case_are_valid
    source = <<~BOTO
      solution "shop"
      project "foo_bar", template: :library
      project "foobar", template: :library
    BOTO

    assert_equal %w[foo_bar foobar], Boto::Botofile.parse(source).projects.map(&:name)
  end

  def test_unknown_template_reports_line
    assert_invalid "Botofile:2: unknown template :foo", <<~BOTO
      solution "shop"
      project "domain", template: :foo
    BOTO
  end

  def test_unknown_reference_reports_line_of_referencing_project
    assert_invalid %(Botofile:3: unknown reference "x"), <<~BOTO
      solution "shop"
      project "domain", template: :library
      project "orders", template: :webapi, refs: %w[x]
    BOTO
  end

  def test_self_reference_reports_line
    assert_invalid %(Botofile:2: project "domain" references itself), <<~BOTO
      solution "shop"
      project "domain", template: :library, refs: %w[domain]
    BOTO
  end

  def test_duplicate_reference_reports_line
    assert_invalid %(Botofile:3: duplicate reference "domain"), <<~BOTO
      solution "shop"
      project "domain", template: :library
      project "orders", template: :webapi, refs: %w[domain domain]
    BOTO
  end

  def test_cycle_is_reported_without_line
    assert_invalid "Botofile: cycle detected: a -> b -> a", <<~BOTO
      solution "shop"
      project "a", template: :library, refs: %w[b]
      project "b", template: :library, refs: %w[a]
    BOTO
  end

  def test_load_reads_file_and_uses_its_path_in_errors
    Dir.mktmpdir do |dir|
      path = File.join(dir, "Botofile")
      File.write(path, VALID)
      assert_equal %w[domain orders], Boto::Botofile.load(path).projects.map(&:name)

      File.write(path, "solution \"shop\"\nproject \"Bad\", template: :library\n")
      error = assert_raises(Boto::Botofile::InvalidError) { Boto::Botofile.load(path) }
      assert_equal %(#{path}:2: invalid project name "Bad"), error.message
    end
  end
end
