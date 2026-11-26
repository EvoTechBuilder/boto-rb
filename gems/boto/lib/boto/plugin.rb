# frozen_string_literal: true

module Boto
  # Base class of project plugins. A plugin wraps the app like Rack middleware: it either
  # calls app.call(env) to continue, or returns a Rack response itself.
  class Plugin
    ORDER = %i[hosts cors secure_headers sessions csrf auth rate_limit].freeze
    SCOPES = %i[global endpoint].freeze
    DEFAULT_SCOPE = :endpoint

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

    def development?
      env_name == "development"
    end

    private

    def configure = nil
  end
end
