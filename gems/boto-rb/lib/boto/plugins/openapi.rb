# frozen_string_literal: true

module Boto
  module Plugins
    # Serves the project's OpenAPI document in every environment. It runs before routing, so the
    # document needs no endpoint and can sit behind :auth.
    class OpenAPI < Boto::Plugin
      scope :global

      GET = "GET"
      HEAD = "HEAD"
      SERVED_METHODS = [GET, HEAD].freeze
      OK = 200
      JSON_TYPE = "application/json"
      AUTH_PLUGIN = :auth
      PATH_PREFIX = "/"
      DEFAULT_PATH = "/openapi.json"
      DEFAULT_VERSION = "0.0.0"

      attr_reader :path

      # The plugin name would be :open_api from the class name, so it is set by hand.
      def self.plugin_name = :openapi

      def auth? = @auth_required

      # The :auth instance protecting the document, or nil. Other plugins answer through it too.
      def guard = @auth

      # The title in the document: the configured one, or the project's namespace name.
      def title = @title || @app&.title

      def attach(app)
        @app = app
        @auth = app.plugins.find { |plugin| plugin.class.plugin_name == AUTH_PLUGIN } if auth?
        check_no_endpoint_on_path!(app)
      end

      # Generated once: every response hands out the same frozen string.
      def start
        document = Boto::OpenAPI.generate(@app, title: title, version: @version, description: @description)
        @document = Boto::OpenAPI::PrefixedDocument.new(document)
      end

      def call(env, app)
        return app.call(env) unless serves?(env)

        @auth ? @auth.call(env, @responder) : @responder.call(env)
      end

      private

      def configure(path: DEFAULT_PATH, version: DEFAULT_VERSION, auth: true, title: nil, description: nil)
        @path = validate_path(path)
        @version = validate_version(version)
        @auth_required = validate_auth(auth)
        @title = validate_title(title)
        @description = validate_description(description)
        @responder = ->(env) { [OK, { "content-type" => JSON_TYPE }, [@document.json_for(env["SCRIPT_NAME"])]] }
      end

      def validate_path(path)
        return path if path.is_a?(String) && path.start_with?(PATH_PREFIX)

        raise ArgumentError, "openapi: path must be a String starting with \"/\", got #{path.inspect}"
      end

      def validate_version(version)
        return version if version.is_a?(String)

        raise ArgumentError, "openapi: version must be a String, got #{version.inspect}"
      end

      def validate_auth(auth)
        return auth if [true, false].include?(auth)

        raise ArgumentError, "openapi: auth must be true or false, got #{auth.inspect}"
      end

      def validate_title(title)
        return title if title.nil? || (title.is_a?(String) && !title.strip.empty?)

        raise ArgumentError, "openapi: title must be a non-blank String or nil, got #{title.inspect}"
      end

      def validate_description(description)
        return description if description.nil? || description.is_a?(String)

        raise ArgumentError, "openapi: description must be a String or nil, got #{description.inspect}"
      end

      def check_no_endpoint_on_path!(app)
        conflict = app.endpoints.find { |endpoint| endpoint.route == [GET, @path] }
        return if conflict.nil?

        raise ArgumentError, "openapi: #{conflict.name} uses GET #{@path}, which the plugin already serves"
      end

      def serves?(env)
        env["PATH_INFO"] == @path && SERVED_METHODS.include?(env["REQUEST_METHOD"])
      end
    end
  end
end
