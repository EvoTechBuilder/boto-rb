# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "json"

# Stand-ins for real plugins: the core must not depend on boto-security.
module AppPluginsFakes
  module Trail
    def self.record(env, name)
      env["x.trail"] = [*env["x.trail"], name]
    end
  end

  class GlobalStamp < Boto::Plugin
    scope :global

    def call(env, app)
      status, headers, body = app.call(env)
      [status, headers.merge("x-global" => "1"), body]
    end
  end

  class Explode < Boto::Plugin
    scope :global

    def call(_env, _app)
      raise "kaboom"
    end
  end

  class Deny < Boto::Plugin
    scope :global

    def call(_env, _app)
      raise Boto::Error::Forbidden, "denied"
    end
  end

  class Tag < Boto::Plugin
    def call(env, app)
      Trail.record(env, "tag")
      status, headers, body = app.call(env)
      [status, headers.merge("x-tag" => "1"), body]
    end
  end

  class Csrf < Boto::Plugin
    def call(env, app)
      Trail.record(env, "csrf")
      app.call(env)
    end
  end

  class Block < Boto::Plugin
    def call(_env, _app)
      Boto::Error::Forbidden.new("blocked").to_response
    end
  end

  module Shop
    class Show < Boto::Endpoint
      get "/users/:id"
      param :id, Integer
      def call(id:) = { id:, trail: env["x.trail"] }
    end
  end

  module Skips
    class Skipping < Boto::Endpoint
      get "/skipping"
      skip :tag
      def call = { skipped: true }
    end

    class Plain < Boto::Endpoint
      get "/plain"
      def call = { plain: true }
    end
  end

  module Blocks
    class Free < Boto::Endpoint
      get "/free"
      skip :block
      def call = { free: true }
    end

    class Guarded < Boto::Endpoint
      get "/guarded"
      def call = { guarded: true }
    end
  end

  module UnknownSkip
    class Show < Boto::Endpoint
      get "/x"
      skip :nope
      def call = {}
    end
  end

  module GlobalSkip
    class Show < Boto::Endpoint
      get "/x"
      skip :global_stamp
      def call = {}
    end
  end
end

module Boto
  class AppPluginsTest < Minitest::Test
    SHOW_ALLOCATIONS = 13
    WARMUP_RUNS = 50
    ALLOCATION_WINDOWS = 2

    def setup
      @error_output = StringIO.new
    end

    def app(namespace: AppPluginsFakes::Shop, plugins: [])
      instances = plugins.map { |klass| klass.new(env_name: "production") }
      Boto::App.new(namespace: namespace, plugins: instances, env_name: "production", error_output: @error_output)
    end

    def get(application, path)
      Rack::MockRequest.new(application).get(path)
    end

    def json(body)
      JSON.parse(body)
    end

    def test_global_plugin_wraps_matched_routes
      res = get(app(plugins: [AppPluginsFakes::GlobalStamp]), "/users/7")
      assert_equal "1", res.headers["x-global"]
      assert_equal 7, json(res.body)["id"]
    end

    def test_global_plugin_also_wraps_unmatched_routes
      res = get(app(plugins: [AppPluginsFakes::GlobalStamp]), "/nope")
      assert_equal 404, res.status
      assert_equal "1", res.headers["x-global"]
    end

    def test_endpoint_plugin_runs_only_on_matched_routes
      application = app(plugins: [AppPluginsFakes::Tag])
      assert_equal "1", get(application, "/users/7").headers["x-tag"]
      assert_nil get(application, "/nope").headers["x-tag"]
    end

    def test_skip_disables_endpoint_plugin_only_for_that_endpoint
      application = app(namespace: AppPluginsFakes::Skips, plugins: [AppPluginsFakes::Tag])
      assert_nil get(application, "/skipping").headers["x-tag"]
      assert_equal "1", get(application, "/plain").headers["x-tag"]
    end

    def test_skip_disables_blocking_plugin_for_that_endpoint
      application = app(namespace: AppPluginsFakes::Blocks, plugins: [AppPluginsFakes::Block])
      assert_equal 200, get(application, "/free").status
      assert_equal 403, get(application, "/guarded").status
    end

    def test_endpoint_plugins_run_in_order_index_order
      application = app(plugins: [AppPluginsFakes::Tag, AppPluginsFakes::Csrf])
      assert_equal %w[csrf tag], json(get(application, "/users/7").body)["trail"]
    end

    def test_path_params_reach_endpoint_when_endpoint_plugins_run
      res = get(app(plugins: [AppPluginsFakes::Tag]), "/users/7")
      assert_equal 7, json(res.body)["id"]
    end

    def test_skip_of_plugin_not_enabled_raises_boot_error
      error = assert_raises(Boto::App::BootError) do
        app(namespace: AppPluginsFakes::UnknownSkip, plugins: [AppPluginsFakes::Tag])
      end
      assert_includes error.message, "skip :nope but plugin :nope is not enabled"
    end

    def test_skip_of_global_plugin_raises_boot_error
      error = assert_raises(Boto::App::BootError) do
        app(namespace: AppPluginsFakes::GlobalSkip, plugins: [AppPluginsFakes::GlobalStamp])
      end
      assert_includes error.message, "cannot skip global plugin :global_stamp"
    end

    def test_unexpected_error_in_global_plugin_returns_500_and_logs
      res = get(app(plugins: [AppPluginsFakes::Explode]), "/users/7")
      assert_equal 500, res.status
      assert_includes @error_output.string, "RuntimeError: kaboom"
    end

    def test_boto_error_in_global_plugin_renders_its_own_response
      res = get(app(plugins: [AppPluginsFakes::Deny]), "/users/7")
      assert_equal 403, res.status
      assert_equal "application/problem+json", res.headers["content-type"]
    end

    def test_endpoint_without_plugins_allocates_the_same_objects_per_request
      application = app
      env = Rack::MockRequest.env_for("/users/7")
      assert_equal SHOW_ALLOCATIONS, measure_allocations { application.call(env) }
    end

    private

    def allocations
      before = GC.stat(:total_allocated_objects)
      yield
      GC.stat(:total_allocated_objects) - before
    end

    # The first run of a measured line allocates a harness object, so the window is repeated and the last run is kept.
    def measure_allocations(&block)
      WARMUP_RUNS.times(&block)
      Array.new(ALLOCATION_WINDOWS) { allocations(&block) }.last
    end
  end
end
