# frozen_string_literal: true

require "fileutils"
require_relative "allocations"
require_relative "support/options"
require_relative "support/scenarios"
require_relative "support/load_test"
require_relative "support/report"
require_relative "support/results"
require_relative "support/comparison"
require_relative "support/runner"

# Benchmarks boto, roda and sinatra with falcon. Options: --quick, --save-baseline, --compare.
module BenchMain
  RESULTS_DIR = File.join(__dir__, "results")
  LATEST_PATH = File.join(RESULTS_DIR, "latest.json")
  BASELINE_PATH = File.join(RESULTS_DIR, "baseline.json")
  NO_BASELINE_MESSAGE = "Sem #{BASELINE_PATH}: nada para comparar. Rode com --save-baseline antes."

  def self.main(argv)
    options = BenchOptions.parse(argv)
    results = run_benchmarks(options)
    puts BenchReport.table(results.slice(*BenchScenarios::FRAMEWORKS))
    status = options.compare ? compare(results) : 0
    save_baseline(results) if options.save_baseline
    status
  end

  def self.run_benchmarks(options)
    load_test = BenchLoadTest.build(quick: options.quick)
    allocations = BenchAllocations.measure_all
    frameworks = BenchRunner.new(load_test: load_test, allocations: allocations, quick: options.quick).run
    document = BenchResults.document(frameworks, tool: load_test.name, ruby: RUBY_VERSION, yjit: RubyVM::YJIT.enabled?)
    BenchResults.write(LATEST_PATH, document)
    document
  end

  def self.compare(results)
    unless File.exist?(BASELINE_PATH)
      warn NO_BASELINE_MESSAGE
      return 0
    end

    rows = BenchComparison.compare(results, BenchResults.read(BASELINE_PATH))
    puts BenchReport.comparison(rows)
    regressions = BenchComparison.regressions(rows)
    warn "REGRESSÃO em #{regressions.size} métrica(s)" if regressions.any?
    regressions.any? ? 1 : 0
  end

  def self.save_baseline(results)
    BenchResults.write(BASELINE_PATH, results)
  end
end

exit BenchMain.main(ARGV) if __FILE__ == $PROGRAM_NAME
