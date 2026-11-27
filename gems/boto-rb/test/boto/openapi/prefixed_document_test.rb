# frozen_string_literal: true

require "test_helper"
require "json"

module Boto
  module OpenAPI
    class PrefixedDocumentTest < Minitest::Test
      DOCUMENT = { "openapi" => "3.1.0", "paths" => {} }.freeze

      def test_without_prefix_is_the_plain_document
        assert_equal JSON.generate(DOCUMENT), PrefixedDocument.new(DOCUMENT).json_for(nil)
      end

      def test_empty_prefix_is_the_plain_document
        assert_equal JSON.generate(DOCUMENT), PrefixedDocument.new(DOCUMENT).json_for("")
      end

      def test_prefix_adds_servers_pointing_at_it
        json = PrefixedDocument.new(DOCUMENT).json_for("/catalogo")
        assert_equal({ "openapi" => "3.1.0", "paths" => {}, "servers" => [{ "url" => "/catalogo" }] }, JSON.parse(json))
      end

      def test_prefix_replaces_servers_already_in_the_document
        document = DOCUMENT.merge("servers" => [{ "url" => "https://old.example" }])
        json = PrefixedDocument.new(document).json_for("/catalogo")
        assert_equal [{ "url" => "/catalogo" }], JSON.parse(json)["servers"]
      end

      def test_same_prefix_is_generated_once
        document = PrefixedDocument.new(DOCUMENT)
        assert_same document.json_for("/catalogo"), document.json_for("/catalogo")
      end

      def test_served_json_is_frozen
        document = PrefixedDocument.new(DOCUMENT)
        assert_predicate document.json_for(nil), :frozen?
        assert_predicate document.json_for("/catalogo"), :frozen?
      end
    end
  end
end
