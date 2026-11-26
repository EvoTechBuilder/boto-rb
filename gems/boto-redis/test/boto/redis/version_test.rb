# frozen_string_literal: true

require "test_helper"

class Boto::Redis::VersionTest < Minitest::Test
  def test_redis_version_matches_boto_version
    assert_equal Boto::VERSION, Boto::Redis::VERSION
  end
end
