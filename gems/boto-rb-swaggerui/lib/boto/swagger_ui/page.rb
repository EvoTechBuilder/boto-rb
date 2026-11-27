# frozen_string_literal: true

require "cgi/escape"
require "json"

module Boto
  module SwaggerUi
    # No inline scripts on purpose: the page works under a strict CSP.
    class Page
      INITIALIZER_NAME = "initializer.js"

      def initialize(title:, document_url:, assets_path:)
        @title = title
        @document_url = document_url
        @assets_path = assets_path
      end

      def html
        <<~HTML.freeze
          <!DOCTYPE html>
          <html lang="en">
          <head>
          <meta charset="utf-8">
          <title>#{escape(@title)}</title>
          <link rel="stylesheet" href="#{escape(asset("swagger-ui.css"))}">
          <link rel="stylesheet" href="#{escape(asset("boto.css"))}">
          </head>
          <body>
          <div id="swagger-ui"></div>
          <script src="#{escape(asset("swagger-ui-bundle.js"))}"></script>
          <script src="#{escape(asset("swagger-ui-standalone-preset.js"))}"></script>
          <script src="#{escape(asset(INITIALIZER_NAME))}"></script>
          </body>
          </html>
        HTML
      end

      def initializer_js
        <<~JS.freeze
          window.onload = function () { window.ui = SwaggerUIBundle({ url: #{document_literal}, dom_id: "#swagger-ui", deepLinking: true, presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset], layout: "StandaloneLayout" }); };
        JS
      end

      private

      def asset(name)
        "#{@assets_path}/#{name}"
      end

      def escape(value)
        CGI.escapeHTML(value)
      end

      # Escaping "</" stops the URL from closing the <script> element it sits in.
      def document_literal
        JSON.generate(@document_url).gsub("</") { '<\/' }
      end
    end
  end
end
