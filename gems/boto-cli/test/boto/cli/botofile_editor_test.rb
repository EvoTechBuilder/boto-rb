# frozen_string_literal: true

require "test_helper"

class Boto::CLI::BotofileEditorTest < Minitest::Test
  SOURCE = <<~BOTOFILE
    solution "shop"

    # domain layer
    project "domain", template: :library
    project "orders", template: :webapi, refs: %w[domain]
    project "billing", template: :webapi, refs: ["domain"]
    project "api", template: :webapi
  BOTOFILE

  def test_appends_refs_option_when_missing
    expected = SOURCE.sub(%(project "api", template: :webapi\n), %(project "api", template: :webapi, refs: %w[domain]\n))
    assert_equal expected, add_ref(SOURCE, "api", "domain")
  end

  def test_adds_to_word_array
    expected = SOURCE.sub("refs: %w[domain]", "refs: %w[domain billing]")
    assert_equal expected, add_ref(SOURCE, "orders", "billing")
  end

  def test_adds_to_bracket_array
    expected = SOURCE.sub('refs: ["domain"]', 'refs: ["domain", "x"]')
    assert_equal expected, add_ref(SOURCE, "billing", "x")
  end

  def test_adds_to_empty_word_array
    assert_equal %(project "a", template: :webapi, refs: %w[x]\n),
                 add_ref(%(project "a", template: :webapi, refs: %w[]\n), "a", "x")
  end

  def test_adds_to_empty_bracket_array
    assert_equal %(project "a", template: :webapi, refs: ["x"]\n),
                 add_ref(%(project "a", template: :webapi, refs: []\n), "a", "x")
  end

  def test_parenthesized_call
    assert_equal %(project("api", template: :webapi, refs: %w[x])\n),
                 add_ref(%(project("api", template: :webapi)\n), "api", "x")
  end

  def test_preserves_comments_and_formatting
    result = add_ref(SOURCE, "api", "domain")
    assert_includes result, "# domain layer\n"
    assert_equal SOURCE.lines.size, result.lines.size
  end

  def test_multibyte_text_before_insertion_point
    source = %(# domínio\nproject "a", template: :library\nproject "b", template: :webapi\n)
    expected = source.sub(%(project "b", template: :webapi\n), %(project "b", template: :webapi, refs: %w[a]\n))
    result = add_ref(source, "b", "a")
    assert_equal expected, result
    assert_equal Encoding::UTF_8, result.encoding
  end

  def test_duplicate_ref_raises
    error = assert_raises(Boto::CLI::Error) { add_ref(SOURCE, "orders", "domain") }
    assert_equal %("orders" already references "domain"), error.message
  end

  def test_missing_project_raises
    error = assert_raises(Boto::CLI::Error) { add_ref(SOURCE, "ghost", "domain") }
    assert_equal %(project "ghost" not found in Botofile), error.message
  end

  def test_syntax_error_raises
    broken = "project \"api\", template: (\n"
    error = assert_raises(Boto::CLI::Error) { add_ref(broken, "api", "x") }
    assert_equal "Botofile has syntax errors", error.message
  end

  def test_constant_refs_raises
    error = assert_raises(Boto::CLI::Error) do
      add_ref(%(project "api", template: :webapi, refs: REFS\n), "api", "x")
    end
    assert_equal "refs must be a literal array", error.message
  end

  private

  def add_ref(source, project, ref)
    Boto::CLI::BotofileEditor.add_ref(source, project: project, ref: ref)
  end
end
