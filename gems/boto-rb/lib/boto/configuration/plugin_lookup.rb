# frozen_string_literal: true

module Boto
  class Configuration
    # Turns a plugin reference (a name or a Boto::Plugin class) into its class, requiring the gem that provides it.
    class PluginLookup
      PLUGIN_NAME = /\A[a-z][a-z0-9_]*\z/
      SECURITY_GEM = "boto/security"

      class << self
        def resolve(plugin_ref)
          case plugin_ref
          when Class then check_class(plugin_ref)
          when Symbol, String then lookup(plugin_ref.to_s)
          else raise ArgumentError, "plugin must be a name or a Boto::Plugin class, got #{plugin_ref.inspect}"
          end
        end

        private

        def check_class(klass)
          raise ArgumentError, "#{klass} must inherit from Boto::Plugin" unless klass < Boto::Plugin

          klass
        end

        def lookup(name)
          raise ArgumentError, "invalid plugin name #{name.inspect}" unless name.match?(PLUGIN_NAME)

          klass = find_plugin(name) ||
                  require_and_find(SECURITY_GEM, name) ||
                  require_and_find("boto/#{name}", name)
          raise ArgumentError, unknown_plugin_message(name) unless klass

          check_class(klass)
        end

        def unknown_plugin_message(name)
          %(unknown plugin :#{name} (add the gem that provides it to the Gemfile, e.g. "boto-rb-security"))
        end

        def find_plugin(name)
          return unless defined?(Boto::Plugins)

          constant = camelize(name)
          Boto::Plugins.const_get(constant, false) if Boto::Plugins.const_defined?(constant, false)
        end

        # Only a missing feature itself is "not found"; a LoadError from a dependency of that feature propagates.
        def require_and_find(feature, name)
          require feature
          find_plugin(name)
        rescue LoadError => error
          raise unless error.path == feature

          nil
        end

        def camelize(name)
          Boto::INFLECTIONS.fetch(name) { name.split("_").map(&:capitalize).join }
        end
      end
    end
  end
end
