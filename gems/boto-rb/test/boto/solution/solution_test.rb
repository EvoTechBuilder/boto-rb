# frozen_string_literal: true

require "test_helper"

class Boto::SolutionTest < Minitest::Test
  def project(name, refs: [])
    Boto::Project.new(name: name, template: :library, refs: refs, line: 1)
  end

  def solution(*projects)
    Boto::Solution.new(name: "shop", projects: projects)
  end

  # a -> b, c ; b -> d ; c -> d
  def diamond
    solution(
      project("a", refs: %w[b c]),
      project("b", refs: %w[d]),
      project("c", refs: %w[d]),
      project("d")
    )
  end

  def names(projects)
    projects.map(&:name)
  end

  def test_topological_order_puts_shared_dependency_first
    assert_equal %w[d b c a], names(diamond.topological_order)
  end

  def test_topological_order_keeps_declaration_order_for_independent_projects
    result = solution(project("x"), project("y"), project("z"))
    assert_equal %w[x y z], names(result.topological_order)
  end

  def test_topological_order_places_dependency_before_declared_dependent
    result = solution(project("b", refs: %w[a]), project("a"), project("c"))
    assert_equal %w[a b c], names(result.topological_order)
  end

  def test_cycle_raises_with_path
    cyclic = solution(project("a", refs: %w[b]), project("b", refs: %w[c]), project("c", refs: %w[a]))
    error = assert_raises(Boto::Solution::CycleError) { cyclic.topological_order }
    assert_equal %w[a b c a], error.path
    assert_equal "cycle detected: a -> b -> c -> a", error.message
  end

  def test_dependencies_of_is_transitive_in_topological_order
    assert_equal %w[d b c], diamond.dependencies_of("a")
  end

  def test_dependencies_of_project_without_refs_is_empty
    assert_equal [], diamond.dependencies_of("d")
  end

  def test_dependents_of_is_transitive_in_declaration_order
    assert_equal %w[a b c], diamond.dependents_of("d")
  end

  def test_dependents_of_excludes_the_project_itself
    assert_equal [], diamond.dependents_of("a")
  end

  def test_project_returns_declared_project
    assert_equal "b", diamond.project("b").name
  end

  def test_project_raises_key_error_for_unknown_name
    error = assert_raises(KeyError) { diamond.project("nope") }
    assert_includes error.message, "nope"
  end

  def test_solution_is_frozen
    assert_predicate diamond, :frozen?
  end
end
