# frozen_string_literal: true

module Boto
  # Base class of project plugins. A plugin wraps the app like Rack middleware: it either
  # calls app.call(env) to continue, or returns a Rack response itself.
  class Plugin
    ORDER = %i[health hosts cors secure_headers sessions csrf auth rate_limit].freeze
    SCOPES = %i[global endpoint].freeze
    DEFAULT_SCOPE = :endpoint
    NO_ERROR_STATUSES = [].freeze
    NO_HEALTH_CHECKS = {}.freeze

    class << self
      def scope(value = nil)
        return @scope || DEFAULT_SCOPE if value.nil?
        raise ArgumentError, "unknown scope #{value.inspect}" unless SCOPES.include?(value)

        @scope = value
      end

      def plugin_name
        underscore(name.split("::").last).to_sym
      end

      def order_index
        ORDER.index(plugin_name) || ORDER.size
      end

      private

      def underscore(camel_case)
        camel_case.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    end

    attr_reader :env_name

    def initialize(env_name:, **options)
      @env_name = env_name
      configure(**options)
    end

    def call(_env, _app)
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    # Receives the Boto::App right before start, so the plugin can call back into it.
    def attach(_app) = nil

    # Runs once, before the first request.
    def start = nil

    # Runs at shutdown; must tolerate being called after its resource is already closed.
    def stop = nil

    # Tells the plugin the app is shutting down, so it can stop accepting new work.
    def drain = nil

    # Named callables that /health/ready runs for this plugin; a value that is truthy means ok.
    def health_checks = NO_HEALTH_CHECKS

    # Statuses this plugin can answer for an endpoint it guards; documented by OpenAPI.
    def error_statuses = NO_ERROR_STATUSES

    def development?
      env_name == "development"
    end

    private

    def configure = nil
  end
end
