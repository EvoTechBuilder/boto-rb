# frozen_string_literal: true

require "test_helper"

class PageTest < Minitest::Test
  ASSETS_PATH = "/docs/assets/5.36.0"

  def test_html_references_assets_under_assets_path
    html = page.html

    assert_includes html, %(<link rel="stylesheet" href="#{ASSETS_PATH}/swagger-ui.css">)
    assert_includes html, %(<script src="#{ASSETS_PATH}/swagger-ui-bundle.js"></script>)
    assert_includes html, %(<script src="#{ASSETS_PATH}/initializer.js"></script>)
    assert_includes html, '<div id="swagger-ui"></div>'
  end

  def test_html_escapes_title
    assert_includes page(title: "<x>").html, "<title>&lt;x&gt;</title>"
  end

  def test_html_has_no_inline_script
    refute_match(/<script(?![^>]*\ssrc=)/, page.html)
  end

  def test_html_and_initializer_are_frozen
    assert_predicate page.html, :frozen?
    assert_predicate page.initializer_js, :frozen?
  end

  def test_initializer_embeds_document_url_as_json
    js = page(document_url: "/docs/openapi.json").initializer_js

    assert_includes js, 'SwaggerUIBundle({ url: "/docs/openapi.json", dom_id: "#swagger-ui"'
  end

  def test_initializer_escapes_closing_tags_in_url
    js = page(document_url: "/x</script><b>").initializer_js

    refute_includes js, "</"
    assert_includes js, '"/x<\/script><b>"'
  end

  private

  def page(title: "Pedidos API", document_url: "/docs/openapi.json")
    Boto::SwaggerUi::Page.new(title: title, document_url: document_url, assets_path: ASSETS_PATH)
  end
end
