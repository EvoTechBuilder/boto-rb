# frozen_string_literal: true

require_relative "../test_helper"
require "json"

# Each .ru is loaded once per process, since loading it again redefines its routes.
class BenchAppsTest < Minitest::Test
  LOADED = {}

  def app(framework, scenario)
    LOADED[[framework, scenario]] ||= Rack::Builder.parse_file(BenchScenarios.app_path(framework, scenario))
  end

  def get(framework, scenario, path)
    status, headers, body = app(framework, scenario).call(Rack::MockRequest.env_for(path))
    text = +""
    body.each { text << _1 }
    body.close if body.respond_to?(:close)
    [status, headers["content-type"], text]
  end

  BenchScenarios::FRAMEWORKS.each do |framework|
    define_method("test_#{framework}_hello_returns_json") do
      status, type, text = get(framework, "hello", "/")
      assert_equal 200, status
      assert_match %r{application/json}, type
      assert_equal({ "hello" => "world" }, JSON.parse(text))
    end

    define_method("test_#{framework}_db_returns_user") do
      status, type, text = get(framework, "db", "/users/500")
      assert_equal 200, status
      assert_match %r{application/json}, type
      assert_equal({ "id" => 500, "name" => "user 500" }, JSON.parse(text))
    end

    define_method("test_#{framework}_db_missing_user_is_404") do
      status, _type, _text = get(framework, "db", "/users/99999")
      assert_equal 404, status
    end
  end
end
