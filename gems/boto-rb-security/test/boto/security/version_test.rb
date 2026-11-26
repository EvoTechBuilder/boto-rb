# frozen_string_literal: true

require "test_helper"

class Boto::Security::VersionTest < Minitest::Test
  def test_security_version_matches_boto_version
    assert_equal Boto::VERSION, Boto::Security::VERSION
  end
end
