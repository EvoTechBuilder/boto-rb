# frozen_string_literal: true

module Boto
  module Plugins
    # Authenticates each request with one strategy (basic, bearer, api_key, ...) and stores the principal in env.
    class Auth < Boto::Plugin
      scope :endpoint

      STRATEGY_FORMAT = /\A[a-z][a-z0-9_]*\z/
      PRINCIPAL_KEY = "boto.principal"

      attr_reader :strategy

      def call(env, app)
        principal = strategy.authenticate(env)
        return Boto::Error::Unauthorized.new(strategy.challenge).to_response unless principal

        env[PRINCIPAL_KEY] = principal
        app.call(env)
      end

      private

      def configure(strategy:, **options)
        @strategy = build_strategy(strategy, options)
      end

      def build_strategy(name, options)
        strategy_class(name).new(**options)
      end

      def strategy_class(name)
        const_name = name.to_s.split("_").map(&:capitalize).join
        unless STRATEGY_FORMAT.match?(name.to_s) && self.class.const_defined?(const_name, false)
          raise ArgumentError, "unknown auth strategy #{name.inspect}"
        end

        self.class.const_get(const_name, false)
      end
    end
  end
end
