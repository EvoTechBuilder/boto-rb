# frozen_string_literal: true

require "test_helper"

class DatabaseGemTest < Minitest::Test
  # The gem's namespace must not shadow the Data class that the core uses inside Boto.
  def test_core_data_define_still_works_with_the_gem_loaded
    result = Boto::Operation::Result.success(1)

    assert_equal 1, result.value
    assert_equal Data, Object.const_get(:Data)
  end

  def test_version_is_the_same_as_the_core
    assert_equal Boto::VERSION, Boto::Database::VERSION
  end
end
