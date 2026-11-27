# frozen_string_literal: true

module Boto
  module Plugins
    # Serves Swagger UI at a path, pointed at the document of the :openapi plugin. Pages and assets are
    # built at boot, so a request is a table lookup that never touches disk or builds a route.
    class SwaggerUi < Boto::Plugin
      scope :global

      GET = "GET"
      HEAD = "HEAD"
      SERVED_METHODS = [GET, HEAD].freeze
      OK = 200
      PATH_PREFIX = "/"
      DEFAULT_PATH = "/docs"
      ASSETS_SEGMENT = "/assets/"
      OPENAPI_PLUGIN = :openapi
      BASIC_CHALLENGE = "Basic"
      HTML_TYPE = "text/html; charset=utf-8"
      JS_TYPE = "text/javascript; charset=utf-8"
      CONTENT_TYPE = "content-type"
      CACHE_CONTROL = "cache-control"
      # The page and initializer embed the document path, which can change without a new asset version.
      NO_CACHE = "no-cache"
      # Asset URLs carry the vendored version, so a new Swagger UI gets new URLs.
      IMMUTABLE = "public, max-age=31536000, immutable"

      def attach(app)
        openapi = find_openapi!(app)
        @guard = openapi.guard
        check_guard!
        check_no_endpoint_on_path!(app)
        @table = build_table(openapi.title, openapi.path)
      end

      def call(env, app)
        return app.call(env) unless serves?(env)
        return answer(env) if @table.key?(env["PATH_INFO"])
        return Boto::Error::NotFound.new.to_response if env["PATH_INFO"].start_with?(@assets_prefix)

        app.call(env)
      end

      private

      def configure(path: DEFAULT_PATH)
        @path = validate_path(path)
        @assets_prefix = "#{@path}#{ASSETS_SEGMENT}"
        @responder = method(:respond)
      end

      def validate_path(path)
        return path if path.is_a?(String) && path.start_with?(PATH_PREFIX) && !path.end_with?(PATH_PREFIX)

        raise ArgumentError, "swagger_ui: path must be a String starting with \"/\" and not ending with \"/\", " \
                             "got #{path.inspect}"
      end

      def serves?(env)
        env["PATH_INFO"].start_with?(@path) && SERVED_METHODS.include?(env["REQUEST_METHOD"])
      end

      def answer(env)
        @guard ? @guard.call(env, @responder) : @responder.call(env)
      end

      def respond(env)
        content_type, body, cache_control = @table.fetch(env["PATH_INFO"])
        [OK, { CONTENT_TYPE => content_type, CACHE_CONTROL => cache_control }, [body]]
      end

      def find_openapi!(app)
        openapi = app.plugins.find { |plugin| plugin.class.plugin_name == OPENAPI_PLUGIN }
        return openapi if openapi

        raise ArgumentError, "swagger_ui: needs app.use :openapi, because the page loads the document it names"
      end

      def check_guard!
        return if @guard.nil? || @guard.strategy.challenge.to_s.start_with?(BASIC_CHALLENGE)

        raise ArgumentError, "swagger_ui: a browser cannot send #{@guard.strategy.challenge.inspect} credentials, " \
                             "so the page could not load the document; " \
                             "use app.use :openapi, auth: false or app.use :auth, strategy: :basic"
      end

      def check_no_endpoint_on_path!(app)
        conflict = app.endpoints.find { |endpoint| endpoint.route == [GET, @path] }
        return if conflict.nil?

        raise ArgumentError, "swagger_ui: #{conflict.name} uses GET #{@path}, which the plugin already serves"
      end

      def build_table(title, document_url)
        assets = Boto::SwaggerUi::Assets.load
        base = "#{@path}#{ASSETS_SEGMENT}#{assets.version}"
        page = Boto::SwaggerUi::Page.new(title: title, document_url: document_url, assets_path: base)
        table = { @path => [HTML_TYPE, page.html, NO_CACHE] }
        table["#{base}/#{Boto::SwaggerUi::Page::INITIALIZER_NAME}"] = [JS_TYPE, page.initializer_js, NO_CACHE]
        Boto::SwaggerUi::Assets::FILES.each_key { |name| table["#{base}/#{name}"] = [*assets.fetch(name), IMMUTABLE] }
        table.transform_values(&:freeze).freeze
      end
    end
  end
end
