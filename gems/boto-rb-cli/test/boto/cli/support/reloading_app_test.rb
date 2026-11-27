# frozen_string_literal: true

require "test_helper"
require "rack/mock"

class Boto::CLI::ReloadingAppTest < Minitest::Test
  OK_BODY = "ok"

  # Hands out one fixed app and records what it was asked for.
  class FakeReloader
    attr_reader :port, :drained

    def initialize(app)
      @app = app
      @drained = false
    end

    def current(port)
      @port = port
      @app
    end

    def drain!
      @drained = true
    end
  end

  def setup
    @app = ->(_env) { [200, { "content-type" => "text/plain" }, [OK_BODY]] }
    @reloader = FakeReloader.new(@app)
    @reloading_app = Boto::CLI::ReloadingApp.new(@reloader, 3000)
  end

  def test_call_delegates_to_the_current_app_of_the_port
    response = Rack::MockRequest.new(@reloading_app).get("/anything")

    assert_equal 200, response.status
    assert_equal OK_BODY, response.body
    assert_equal 3000, @reloader.port
  end

  def test_drain_delegates_to_the_reloader
    @reloading_app.drain!

    assert @reloader.drained
  end
end
