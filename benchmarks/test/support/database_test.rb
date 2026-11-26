# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../support/database"

class BenchDatabaseTest < Minitest::Test
  def setup
    @db = BenchDatabase.connect
  end

  def test_seeds_user_count_rows
    assert_equal BenchDatabase::USER_COUNT, @db[:users].count
  end

  def test_names_follow_the_id
    assert_equal({ id: 500, name: "user 500" }, @db[:users].where(id: 500).first)
  end
end
