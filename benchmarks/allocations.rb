# frozen_string_literal: true

require "rack"
require "rack/builder"
require_relative "support/scenarios"
require_relative "support/report"

# Allocations per request, counted in-process with GC.stat around each app.call.
module BenchAllocations
  REQUEST_COUNT = 2_000
  WARMUP_COUNT = 200
  HEADERS = ["framework", "scenario", "allocations/request"].freeze

  def self.measure_all
    BenchScenarios::FRAMEWORKS.to_h do |framework|
      [framework, BenchScenarios::NAMES.to_h { |scenario| [scenario, measure(framework, scenario)] }]
    end
  end

  def self.measure(framework, scenario)
    app = load_app(BenchScenarios.app_path(framework, scenario))
    warm_up(app, scenario)
    envs = build_envs(scenario, REQUEST_COUNT, offset: WARMUP_COUNT)
    total = envs.sum { |env| allocations_for(app, env) }
    (total.to_f / envs.size).round(2)
  end

  def self.load_app(path)
    Rack::Builder.parse_file(path)
  end

  def self.warm_up(app, scenario)
    build_envs(scenario, WARMUP_COUNT, offset: 0).each { |env| consume(app.call(env)) }
  end

  def self.build_envs(scenario, count, offset:)
    Array.new(count) do |index|
      Rack::MockRequest.env_for(BenchScenarios.path_for(scenario, offset + index))
    end
  end

  def self.allocations_for(app, env)
    before = allocated_objects
    consume(app.call(env))
    allocated_objects - before
  end

  def self.allocated_objects = GC.stat(:total_allocated_objects)

  def self.consume(response)
    _status, _headers, body = response
    body.each { }
    body.close if body.respond_to?(:close)
  end

  def self.print_table(results)
    rows = results.flat_map do |framework, scenarios|
      scenarios.map { |scenario, value| [framework, scenario, value.to_s] }
    end
    puts BenchReport.format_rows([HEADERS, *rows])
  end
end

if __FILE__ == $PROGRAM_NAME
  BenchAllocations.print_table(BenchAllocations.measure_all)
end
