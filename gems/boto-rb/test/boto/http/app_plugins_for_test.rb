# frozen_string_literal: true

require "test_helper"
require "stringio"

# Configuration looks up :auth under Boto::Plugins; the stand-in is attached here and removed after each test.
module Boto
  module Plugins; end
end

module AppPluginsForFakes
  class Global < Boto::Plugin
    scope :global
  end

  class Guard < Boto::Plugin
  end

  module Stand
    # A name ending in Auth keeps plugin_name :auth, so `authenticate` builds this instance.
    class Auth < Boto::Plugin
      private

      def configure(strategy:)
        @strategy = strategy
      end
    end
  end

  module Shop
    class Open < Boto::Endpoint
      get "/open"
    end

    class Skipped < Boto::Endpoint
      get "/skipped"
      skip :guard
    end

    class Secured < Boto::Endpoint
      get "/secured"
      authenticate :bearer
    end
  end
end

class Boto::AppPluginsForTest < Minitest::Test
  def setup
    Boto::Plugins.const_set(:Auth, AppPluginsForFakes::Stand::Auth)
    @global = AppPluginsForFakes::Global.new(env_name: "production")
    @guard = AppPluginsForFakes::Guard.new(env_name: "production")
    @app = build_app([@global, @guard])
  end

  def teardown
    Boto::Plugins.send(:remove_const, :Auth)
  end

  def test_open_endpoint_runs_the_global_and_the_endpoint_plugins
    assert_equal [@global, @guard], @app.plugins_for(AppPluginsForFakes::Shop::Open)
  end

  def test_skipped_endpoint_plugin_is_left_out
    assert_equal [@global], @app.plugins_for(AppPluginsForFakes::Shop::Skipped)
  end

  def test_authenticated_endpoint_includes_its_own_auth_instance_once
    auth = @app.auth_for(AppPluginsForFakes::Shop::Secured)
    plugins = @app.plugins_for(AppPluginsForFakes::Shop::Secured)

    assert_equal [@global, auth, @guard].map(&:object_id).sort, plugins.map(&:object_id).sort
    assert_equal 1, plugins.count { |plugin| plugin.equal?(auth) }
  end

  private

  def build_app(plugins)
    Boto::App.new(namespace: AppPluginsForFakes::Shop, plugins: plugins, env_name: "production",
                  error_output: StringIO.new)
  end
end
