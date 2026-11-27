# frozen_string_literal: true

require "test_helper"

class Boto::Env::ParserTest < Minitest::Test
  def parse(text) = Boto::Env::Parser.parse(text, path: ".env")

  def assert_parse_error(text, message)
    error = assert_raises(Boto::Env::ParseError) { parse(text) }
    assert_equal message, error.message
  end

  def test_parses_plain_assignments
    assert_equal({ "A" => "1", "B_2" => "two" }, parse("A=1\nB_2=two\n"))
  end

  def test_ignores_blank_lines_and_comments
    assert_equal({ "A" => "1" }, parse("\n   \n# comment\n   # indented comment\nA=1\n"))
  end

  def test_accepts_and_removes_export_prefix
    assert_equal({ "A" => "1" }, parse("export A=1\n"))
  end

  def test_trims_spaces_around_key_and_equal_sign
    assert_equal({ "A" => "1" }, parse("  A  =  1  \n"))
  end

  def test_unquoted_value_drops_inline_comment
    assert_equal({ "A" => "1" }, parse("A=1 # x\n"))
  end

  def test_hash_without_leading_space_is_part_of_value
    assert_equal({ "A" => "a#b" }, parse("A=a#b\n"))
  end

  def test_empty_value
    assert_equal({ "A" => "" }, parse("A=\n"))
  end

  def test_value_keeps_equal_signs
    assert_equal({ "URL" => "a=b" }, parse("URL=a=b\n"))
  end

  def test_double_quotes_interpret_escapes
    assert_equal({ "A" => "x\ny\tz\"w\\" }, parse(%(A="x\\ny\\tz\\"w\\\\"\n)))
  end

  def test_double_quotes_keep_other_escapes_and_allow_comment
    assert_equal({ "A" => "a\\qb" }, parse(%(A="a\\qb" # note\n)))
  end

  def test_single_quotes_are_literal
    assert_equal({ "A" => 'sem $interpolação \n' }, parse("A='sem $interpolação \\n'\n"))
  end

  def test_command_substitution_and_interpolation_stay_literal
    text = %(A=$(echo x)\nB=${HOME}\nC="$(echo x)"\n)
    assert_equal({ "A" => "$(echo x)", "B" => "${HOME}", "C" => "$(echo x)" }, parse(text))
  end

  def test_last_duplicate_key_wins
    assert_equal({ "A" => "2" }, parse("A=1\nA=2\n"))
  end

  def test_result_is_frozen_with_frozen_values
    vars = parse("A=1\n")
    assert_predicate vars, :frozen?
    assert_predicate vars["A"], :frozen?
  end

  def test_unclosed_double_quote_is_an_error_without_the_value
    assert_parse_error(%(A=1\nSECRET="abc\n), ".env:2: invalid line")
  end

  def test_unclosed_single_quote_is_an_error
    assert_parse_error("A='abc\n", ".env:1: invalid line")
  end

  def test_text_after_closing_quote_is_an_error
    assert_parse_error(%(A="abc"x\n), ".env:1: invalid line")
  end

  def test_line_without_equal_sign_is_an_error
    assert_parse_error("JUST_A_WORD\n", ".env:1: invalid line")
  end

  def test_invalid_key_is_reported_by_name
    assert_parse_error("1BAD=value\n", %(.env:1: invalid key "1BAD"))
  end

  def test_missing_key_is_reported_by_name
    assert_parse_error("=value\n", %(.env:1: invalid key ""))
  end

  def test_error_uses_the_given_path_and_never_shows_the_value
    error = assert_raises(Boto::Env::ParseError) do
      Boto::Env::Parser.parse("OK=1\nSECRET=\"abc\n", path: "/app/.env.local")
    end
    assert_equal "/app/.env.local:2: invalid line", error.message
    refute_includes error.message, "abc"
  end
end
