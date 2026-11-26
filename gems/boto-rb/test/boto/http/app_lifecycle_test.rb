# frozen_string_literal: true

require "test_helper"
require "stringio"

# Configuration looks up :auth under Boto::Plugins; the module is created here only if no other test did.
module Boto
  module Plugins; end
end

module AppLifecycleFakes
  class Tracked < Boto::Plugin
    private

    def configure(log:)
      @log = log
    end

    def record(event)
      @log << [self.class.plugin_name, event]
    end
  end

  class Alpha < Tracked
    def start = record(:start)
    def stop = record(:stop)
  end

  class Beta < Tracked
    def start = record(:start)
    def stop = record(:stop)
  end

  class Gamma < Tracked
    def start = record(:start)
    def stop = record(:stop)
  end

  class Broken < Tracked
    def start = raise("boom")
    def stop = record(:stop)
  end

  class Unstoppable < Tracked
    def start = record(:start)
    def stop = raise("stop boom")
  end

  class Silent < Boto::Plugin; end

  module Stand
    # Stands in for boto-rb-security's :auth; a name ending in Auth keeps plugin_name :auth.
    class Auth < Boto::Plugin
      attr_reader :events

      def start = @events << :start
      def stop = @events << :stop

      private

      def configure(strategy:)
        @events = []
      end
    end
  end

  module Empty; end

  module Secured
    class Me < Boto::Endpoint
      get "/me"
      authenticate :bearer
      def call = {}
    end
  end
end

module Boto
  class AppLifecycleTest < Minitest::Test
    def setup
      @log = []
      @error_output = StringIO.new
      Boto::Plugins.const_set(:Auth, AppLifecycleFakes::Stand::Auth)
    end

    def teardown
      Boto::Plugins.send(:remove_const, :Auth)
    end

    def app(plugins: [], namespace: AppLifecycleFakes::Empty)
      Boto::App.new(namespace: namespace, plugins: plugins, env_name: "production", error_output: @error_output)
    end

    def tracked(klass)
      klass.new(env_name: "production", log: @log)
    end

    def test_start_runs_plugins_in_order_and_stop_reverses_them
      application = app(plugins: [tracked(AppLifecycleFakes::Alpha), tracked(AppLifecycleFakes::Beta)])
      application.start
      application.stop

      assert_equal [[:alpha, :start], [:beta, :start], [:beta, :stop], [:alpha, :stop]], @log
    end

    def test_start_and_stop_twice_call_each_plugin_once
      application = app(plugins: [tracked(AppLifecycleFakes::Alpha)])
      2.times { application.start }
      2.times { application.stop }

      assert_equal [[:alpha, :start], [:alpha, :stop]], @log
    end

    def test_stop_without_start_does_nothing
      app(plugins: [tracked(AppLifecycleFakes::Alpha)]).stop

      assert_empty @log
    end

    def test_failed_start_stops_already_started_plugins_in_reverse
      application = app(plugins: [tracked(AppLifecycleFakes::Alpha), tracked(AppLifecycleFakes::Beta),
                                  tracked(AppLifecycleFakes::Broken)])
      error = assert_raises(Boto::App::BootError) { application.start }

      assert_equal "plugin :broken failed to start: RuntimeError: boom", error.message
      assert_kind_of RuntimeError, error.cause
      assert_equal [[:alpha, :start], [:beta, :start], [:beta, :stop], [:alpha, :stop]], @log
    end

    def test_failing_stop_is_logged_and_other_plugins_still_stop
      application = app(plugins: [tracked(AppLifecycleFakes::Alpha), tracked(AppLifecycleFakes::Unstoppable),
                                  tracked(AppLifecycleFakes::Beta)])
      application.start
      application.stop

      assert_includes @error_output.string, "RuntimeError: stop boom"
      assert_equal [[:alpha, :start], [:unstoppable, :start], [:beta, :start], [:beta, :stop], [:alpha, :stop]], @log
    end

    def test_authenticate_instance_is_started_and_stopped
      application = app(namespace: AppLifecycleFakes::Secured)
      auth = application.auth_for(AppLifecycleFakes::Secured::Me)
      application.start
      application.stop

      assert_equal [:start, :stop], auth.events
    end

    def test_plugin_without_its_own_start_and_stop_is_a_no_op
      application = app(plugins: [AppLifecycleFakes::Silent.new(env_name: "production"), tracked(AppLifecycleFakes::Alpha)])
      application.start
      application.stop

      assert_equal [[:alpha, :start], [:alpha, :stop]], @log
      assert_empty @error_output.string
    end
  end
end
