# frozen_string_literal: true

require "test_helper"

class Boto::CLI::AffectedProjectsTest < Minitest::Test
  def test_library_change_affects_its_dependents_in_order
    assert_equal %w[domain orders billing], affected(["libs/domain/lib/a.rb"])
  end

  def test_service_change_affects_only_itself
    assert_equal %w[billing], affected(["services/billing/app.rb"])
  end

  def test_file_outside_projects_affects_nothing
    assert_equal [], affected(["README.md"])
  end

  def test_botofile_change_affects_every_project
    assert_equal %w[domain orders billing tools], affected(["Botofile"])
  end

  def test_path_prefix_lookalike_does_not_match
    assert_equal [], affected(["libs/domainx/a.rb"])
  end

  private

  def affected(changed_files)
    Boto::CLI::AffectedProjects.call(changed_files, solution)
  end

  def solution
    Boto::Botofile.parse(<<~BOTO)
      solution "shop"
      project "domain", template: :library
      project "orders", template: :webapi, refs: ["domain"]
      project "billing", template: :webapi, refs: ["orders"]
      project "tools", template: :library
    BOTO
  end
end
