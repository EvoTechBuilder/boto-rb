# frozen_string_literal: true

module Boto
  module Gateway
    # Rack app for the panel under /_boto. Read-only: GET and HEAD, the page is built on each request.
    class Panel
      PATH = "/_boto"
      HTML_PATH = PATH
      JSON_PATH = "/_boto/services.json"
      CSS_PATH = "/_boto/panel.css"
      STYLESHEET_FILE = File.join(__dir__, "assets", "panel.css")
      TEMPLATE_FILE = File.join(__dir__, "panel.html.erb")
      READ_METHODS = %w[GET HEAD].freeze
      ALLOW = "GET, HEAD"
      HTML_TYPE = "text/html; charset=utf-8"
      JSON_TYPE = "application/json; charset=utf-8"
      CSS_TYPE = "text/css; charset=utf-8"
      TEXT_TYPE = "text/plain; charset=utf-8"
      NO_STORE = "no-store"

      def initialize(gateway:, mounts:, env_name:, stylesheet: File.read(STYLESHEET_FILE, encoding: Encoding::UTF_8),
                     html: HtmlView.new(HtmlView.template))
        @gateway = gateway
        @mounts = mounts
        @env_name = env_name
        @stylesheet = stylesheet.freeze
        @html = html
      end

      def call(env)
        return method_not_allowed unless READ_METHODS.include?(env["REQUEST_METHOD"])

        case env["PATH_INFO"]
        when HTML_PATH then html(env)
        when JSON_PATH then json(env)
        when CSS_PATH then [200, { "content-type" => CSS_TYPE }, [@stylesheet]]
        else text(404, "Not Found")
        end
      end

      private

      def html(env)
        [200, { "content-type" => HTML_TYPE, "cache-control" => NO_STORE }, [@html.render(page(env))]]
      end

      def json(env)
        [200, { "content-type" => JSON_TYPE, "cache-control" => NO_STORE }, [JsonView.render(page(env))]]
      end

      def page(env)
        Page.build(gateway_app: @gateway, mounts: @mounts, env_name: @env_name,
                   host: env["HTTP_HOST"], base: env["SCRIPT_NAME"].to_s)
      end

      def method_not_allowed
        [405, { "content-type" => TEXT_TYPE, "allow" => ALLOW }, ["Method Not Allowed"]]
      end

      def text(status, body)
        [status, { "content-type" => TEXT_TYPE }, [body]]
      end
    end
  end
end
