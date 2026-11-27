# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class AssetsTest < Minitest::Test
  CSS_TYPE = "text/css; charset=utf-8"
  JS_TYPE = "text/javascript; charset=utf-8"
  SVG_TYPE = "image/svg+xml"

  def test_load_reads_vendored_and_brand_files
    assets = Boto::SwaggerUi::Assets.load

    assert_equal "5.36.0", assets.version
    assert_equal CSS_TYPE, assets.fetch("swagger-ui.css").first
    assert_equal JS_TYPE, assets.fetch("swagger-ui-bundle.js").first
    assert_equal JS_TYPE, assets.fetch("swagger-ui-standalone-preset.js").first
    assert_equal CSS_TYPE, assets.fetch("boto.css").first
    assert_equal SVG_TYPE, assets.fetch("ruby.svg").first
    Boto::SwaggerUi::Assets::FILES.each_key do |name|
      refute_empty assets.fetch(name).last, name
    end
  end

  def test_files_lists_every_servable_name
    assert_equal %w[swagger-ui.css swagger-ui-bundle.js swagger-ui-standalone-preset.js boto.css ruby.svg],
                 Boto::SwaggerUi::Assets::FILES.keys
  end

  def test_fetch_returns_nil_for_unknown_or_traversal_names
    assets = Boto::SwaggerUi::Assets.load(vendor_dir: fake_vendor_dir, brand_dir: fake_brand_dir)

    assert_nil assets.fetch("nope")
    assert_nil assets.fetch("../LICENSE")
    assert_nil assets.fetch("../vendor/swagger-ui/LICENSE")
  end

  def test_fetch_returns_same_frozen_pair
    assets = Boto::SwaggerUi::Assets.load(vendor_dir: fake_vendor_dir, brand_dir: fake_brand_dir)
    pair = assets.fetch("swagger-ui.css")

    assert_same pair, assets.fetch("swagger-ui.css")
    assert_predicate pair, :frozen?
    assert_predicate pair.last, :frozen?
    assert_predicate assets.version, :frozen?
    assert_predicate assets, :frozen?
  end

  def test_load_reads_from_given_dirs
    assets = Boto::SwaggerUi::Assets.load(vendor_dir: fake_vendor_dir, brand_dir: fake_brand_dir)

    assert_equal "9.9.9", assets.version
    assert_equal [CSS_TYPE, "css-body"], assets.fetch("swagger-ui.css")
    assert_equal [JS_TYPE, "js-body"], assets.fetch("swagger-ui-bundle.js")
    assert_equal [JS_TYPE, "preset-body"], assets.fetch("swagger-ui-standalone-preset.js")
    assert_equal [CSS_TYPE, "brand-css"], assets.fetch("boto.css")
    assert_equal [SVG_TYPE, "brand-svg"], assets.fetch("ruby.svg")
  end

  def teardown
    FileUtils.remove_entry(@fake_vendor_dir) if @fake_vendor_dir
    FileUtils.remove_entry(@fake_brand_dir) if @fake_brand_dir
  end

  private

  def fake_vendor_dir
    @fake_vendor_dir ||= begin
      dir = Dir.mktmpdir
      File.write(File.join(dir, "VERSION"), "9.9.9\n")
      File.binwrite(File.join(dir, "swagger-ui.css"), "css-body")
      File.binwrite(File.join(dir, "swagger-ui-bundle.js"), "js-body")
      File.binwrite(File.join(dir, "swagger-ui-standalone-preset.js"), "preset-body")
      dir
    end
  end

  def fake_brand_dir
    @fake_brand_dir ||= begin
      dir = Dir.mktmpdir
      File.binwrite(File.join(dir, "boto.css"), "brand-css")
      File.binwrite(File.join(dir, "ruby.svg"), "brand-svg")
      dir
    end
  end
end
