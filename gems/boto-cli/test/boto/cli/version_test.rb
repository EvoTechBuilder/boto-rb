# frozen_string_literal: true

require "test_helper"

class Boto::CLI::VersionTest < Minitest::Test
  def test_cli_version_matches_boto_version
    assert_equal Boto::VERSION, Boto::CLI::VERSION
  end
end
