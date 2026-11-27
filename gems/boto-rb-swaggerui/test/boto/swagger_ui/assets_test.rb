# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class AssetsTest < Minitest::Test
  CSS_TYPE = "text/css; charset=utf-8"
  JS_TYPE = "text/javascript; charset=utf-8"

  def test_load_reads_vendored_files
    assets = Boto::SwaggerUi::Assets.load

    assert_equal "5.36.0", assets.version
    assert_equal CSS_TYPE, assets.fetch("swagger-ui.css").first
    assert_equal JS_TYPE, assets.fetch("swagger-ui-bundle.js").first
    refute_empty assets.fetch("swagger-ui.css").last
    refute_empty assets.fetch("swagger-ui-bundle.js").last
  end

  def test_fetch_returns_nil_for_unknown_or_traversal_names
    assets = Boto::SwaggerUi::Assets.load(dir: fake_dir)

    assert_nil assets.fetch("nope")
    assert_nil assets.fetch("../LICENSE")
  end

  def test_fetch_returns_same_frozen_pair
    assets = Boto::SwaggerUi::Assets.load(dir: fake_dir)
    pair = assets.fetch("swagger-ui.css")

    assert_same pair, assets.fetch("swagger-ui.css")
    assert_predicate pair, :frozen?
    assert_predicate pair.last, :frozen?
    assert_predicate assets.version, :frozen?
    assert_predicate assets, :frozen?
  end

  def test_load_reads_from_given_dir
    assets = Boto::SwaggerUi::Assets.load(dir: fake_dir)

    assert_equal "9.9.9", assets.version
    assert_equal [CSS_TYPE, "css-body"], assets.fetch("swagger-ui.css")
    assert_equal [JS_TYPE, "js-body"], assets.fetch("swagger-ui-bundle.js")
  end

  def teardown
    FileUtils.remove_entry(@fake_dir) if @fake_dir
  end

  private

  def fake_dir
    @fake_dir ||= begin
      dir = Dir.mktmpdir
      File.write(File.join(dir, "VERSION"), "9.9.9\n")
      File.binwrite(File.join(dir, "swagger-ui.css"), "css-body")
      File.binwrite(File.join(dir, "swagger-ui-bundle.js"), "js-body")
      dir
    end
  end
end
