# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class Boto::CLI::ExeTest < Minitest::Test
  GEM_ROOT = File.expand_path("../../..", __dir__)

  def test_without_arguments_prints_help_and_exits_zero
    stdout, _stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", "exe/boto", chdir: GEM_ROOT)

    assert_predicate status, :success?
    assert_includes stdout, "new"
  end
end
