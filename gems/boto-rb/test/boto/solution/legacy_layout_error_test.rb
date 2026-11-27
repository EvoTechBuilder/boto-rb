# frozen_string_literal: true

require "test_helper"

class Boto::LegacyLayoutErrorTest < Minitest::Test
  def test_message_has_one_explanation_and_fix_line_per_project
    projects = [
      Boto::Project.new(name: "pedidos", template: :webapi, refs: [], line: 1),
      Boto::Project.new(name: "painel", template: :microservice, refs: [], line: 2)
    ]

    expected = <<~MESSAGE.chomp
      project "pedidos" is in services/pedidos; HTTP projects now live in apps/pedidos.
      Fix: git mv services/pedidos apps/pedidos
      project "painel" is in services/painel; HTTP projects now live in apps/painel.
      Fix: git mv services/painel apps/painel
    MESSAGE

    assert_equal expected, Boto::LegacyLayoutError.new(projects).message
  end

  def test_exposes_project_names
    projects = [Boto::Project.new(name: "pedidos", template: :webapi, refs: [], line: 1)]

    error = Boto::LegacyLayoutError.new(projects)

    assert_equal ["pedidos"], error.projects
    assert_kind_of StandardError, error
  end
end
