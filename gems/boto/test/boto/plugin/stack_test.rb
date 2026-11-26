# frozen_string_literal: true

require "test_helper"

module Boto
  class Plugin
    class StackTest < Minitest::Test
      class Recorder < Boto::Plugin
        def call(env, app)
          env[:trail] << @label
          app.call(env)
        end

        private

        def configure(label:)
          @label = label
        end
      end

      class Halter < Boto::Plugin
        def call(_env, _app)
          [403, {}, ["halted"]]
        end
      end

      def test_empty_list_returns_the_inner_app
        inner = ->(_env) { [200, {}, ["ok"]] }

        assert_same inner, Boto::Plugin::Stack.build([], inner)
      end

      def test_first_plugin_is_the_outermost
        env = { trail: [] }
        inner = lambda do |inner_env|
          inner_env[:trail] << :inner
          [200, {}, ["ok"]]
        end
        app = Boto::Plugin::Stack.build([recorder(:first), recorder(:second)], inner)

        status, _headers, body = app.call(env)

        assert_equal %i[first second inner], env[:trail]
        assert_equal 200, status
        assert_equal ["ok"], body
      end

      def test_plugin_returning_a_response_stops_the_chain
        env = { trail: [] }
        inner = ->(_env) { flunk "inner app must not run" }
        app = Boto::Plugin::Stack.build([recorder(:before), Halter.new(env_name: "test"), recorder(:after)], inner)

        status, _headers, _body = app.call(env)

        assert_equal 403, status
        assert_equal [:before], env[:trail]
      end

      private

      def recorder(label)
        Recorder.new(env_name: "test", label: label)
      end
    end
  end
end
