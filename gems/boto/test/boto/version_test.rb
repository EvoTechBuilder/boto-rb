# frozen_string_literal: true

require "test_helper"

class Boto::VersionTest < Minitest::Test
  def test_version_is_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, Boto::VERSION)
  end
end
