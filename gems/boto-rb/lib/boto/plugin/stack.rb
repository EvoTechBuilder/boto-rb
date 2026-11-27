# frozen_string_literal: true

module Boto
  class Plugin
    # Chains plugins around an inner app. The first plugin is the outermost one.
    # Lifecycle-only plugins (no #call of their own, e.g. :database) are left out, so they cost nothing per request.
    module Stack
      def self.build(plugins, inner)
        plugins.select(&:handles_requests?).reverse.reduce(inner) { |app, plugin| wrap(plugin, app) }
      end

      def self.wrap(plugin, app)
        ->(env) { plugin.call(env, app) }
      end
      private_class_method :wrap
    end
  end
end
