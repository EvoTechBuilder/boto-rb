# frozen_string_literal: true

require "test_helper"

class EntityMapperTest < Minitest::Test
  Pair = Data.define(:left, :right)

  def setup
    @mapper = Boto::Database::EntityMapper.new(Pair)
  end

  def test_build_keeps_only_the_entity_members
    pair = @mapper.build(left: 1, right: 2, extra: "ignored")

    assert_equal Pair.new(left: 1, right: 2), pair
  end

  def test_build_fails_when_a_member_is_missing_from_the_row
    assert_raises(ArgumentError) { @mapper.build(left: 1) }
  end

  def test_member_accepts_strings_and_rejects_unknown_names
    assert_equal :left, @mapper.member("left")
    assert_equal :right, @mapper.member(:right)

    error = assert_raises(ArgumentError) { @mapper.member("extra") }

    assert_equal %(unknown field "extra" for EntityMapperTest::Pair), error.message
  end

  def test_missing_columns_lists_the_members_without_a_column
    assert_equal [:right], @mapper.missing_columns([:left, :other])
    assert_empty @mapper.missing_columns([:left, :right])
  end
end
