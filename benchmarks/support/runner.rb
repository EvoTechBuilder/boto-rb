# frozen_string_literal: true

require_relative "scenarios"
require_relative "server"
require_relative "results"

# Runs every framework x scenario: a fresh falcon per round, then the load tool against it.
# Progress goes to `out` per round, so a CI log without a terminal does not look stuck.
class BenchRunner
  ROUNDS = 3
  QUICK_ROUNDS = 1
  FAILED_LABEL = "falhou"

  def initialize(load_test:, allocations:, quick:, out: $stdout, server_factory: BenchServer.method(:open))
    @load_test = load_test
    @allocations = allocations
    @rounds = quick ? QUICK_ROUNDS : ROUNDS
    @out = out
    @server_factory = server_factory
    @total = BenchScenarios.combinations.size * @rounds
    @step = 0
  end

  def run
    announce
    BenchScenarios.matrix { |framework, scenario| measure(framework, scenario) }
  end

  def measure(framework, scenario)
    samples = Array.new(@rounds) { |index| sample(framework, scenario, index + 1) }
    BenchResults.summarize(samples, allocations: @allocations.fetch(framework).fetch(scenario))
  end

  def sample(framework, scenario, round)
    @step += 1
    write("[#{@step}/#{@total}] #{framework} #{scenario} round #{round}/#{@rounds} ...")
    result = measure_round(framework, scenario)
    write(" #{format_result(result)}\n")
    result
  end

  private

  def announce
    combinations = BenchScenarios.combinations.size
    write("Benchmark: #{BenchScenarios::FRAMEWORKS.join(", ")} (#{@load_test.name}), " \
          "#{@total} medições (#{combinations} combinações x #{@rounds} rodadas)\n")
  end

  def measure_round(framework, scenario)
    @server_factory.call(BenchScenarios.app_path(framework, scenario)) do |server|
      measure_against(server, BenchScenarios.load_path(scenario), BenchScenarios.headers_for(scenario))
    end
  rescue StandardError => error
    write(" #{FAILED_LABEL}: #{error.message}\n")
    raise
  end

  def measure_against(server, path, headers)
    server.ensure_ok!(path, headers: headers)
    url = "#{server.url}#{path}"
    @load_test.warm_up(url, headers: headers)
    @load_test.measure(url, headers: headers)
  end

  def format_result(result)
    "#{result[:rps].round} req/s, p99 #{result[:p99_ms].round(2)} ms"
  end

  def write(text)
    @out.print(text)
    @out.flush
  end
end
